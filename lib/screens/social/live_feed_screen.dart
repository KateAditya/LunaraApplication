// ignore_for_file: use_build_context_synchronously, unused_local_variable
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/realtime_sync_manager.dart';
import '../../services/optimistic_action_guard.dart';
import 'party_plan_detail_screen.dart';
import 'plan_hub_screen.dart';
import 'post_detail_screen.dart';
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
import '../discovery/digital_ticket_screen.dart';
import '../post_booking/ticket_pocket_screen.dart';
import '../../widgets/booking_cancellation_dialog.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/lunara_profile_image.dart';
import '../profile/profile_screen.dart';
import '../../models/user.dart';
import '../../dialogs/strangers_meet_start_dialog.dart';
import '../../dialogs/strangers_meet_end_dialog.dart';
import '../../dialogs/strangers_meet_host_cancellation_dialog.dart';
import '../../dialogs/strangers_meet_cancellation_dialog.dart';
import '../../widgets/upcoming_night_host_confirm_dialog.dart';
import '../../utils/lunara_date_formatter.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Unified Notification Item Schema
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationAction {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final IconData? icon;
  final Color? color;
  final bool isLoading;

  NotificationAction({
    required this.label,
    required this.onTap,
    this.isPrimary = true,
    this.icon,
    this.color,
    this.isLoading = false,
  });
}

class UnifiedNotificationItem {
  final String id;
  final String
  category; // 'booking', 'party_plan', 'stranger_meet', 'payment', 'wallet', 'chat', 'system', 'promotion', 'cancellation', 'reminder'
  final String title;
  final String body;
  final DateTime createdAt;
  final String timeAgo;
  final bool isRead;
  final bool isExpired;
  final String priority; // 'CRITICAL', 'HIGH', 'NORMAL', 'LOW'
  final String?
  badgeText; // 'NEW', 'ACTION REQUIRED', 'EXPIRES SOON', 'REMINDER', 'COMPLETED'
  final Color accentColor;
  final IconData categoryIcon;
  final String? avatarUrl;
  final Map<String, dynamic>? senderUser;
  final String? actionButtonText;
  final VoidCallback? onActionTap;
  final List<NotificationAction>? actions;
  final Map<String, dynamic> rawData;
  final String? userRoleLabel;
  final Map<String, dynamic>? partnerUser;
  final String? partnerRoleLabel;
  final String? statusSummary;

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
    this.userRoleLabel,
    this.partnerUser,
    this.partnerRoleLabel,
    this.statusSummary,
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;

  List<Map<String, dynamic>> _feedItems = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _largePartyBookings = [];
  List<Map<String, dynamic>> _userBookings = [];
  List<UnifiedNotificationItem> _cachedTimeline = [];
  bool _isLoading = true;
  bool _isFetchingFeed = false;
  Timer? _pollingTimer;
  String? _sessionUserId;

  // Selected Category Filter for Bottom Sheet
  String _selectedCategoryFilter = 'ALL';

  // Selected Status Filter Pills: 'ALL', 'REQUESTS', 'PENDING', 'PAYMENT', 'CONFIRMED', 'SYSTEM'
  String _selectedStatusPill = 'ALL';

  // Razorpay for large party payments
  Razorpay? _razorpay;
  String? _pendingLargePartyBookingId;

  // Active action loaders & payment tracking
  final Set<String> _activeActionKeys = <String>{};
  String? _processingPaymentBookingId;

  void refreshFeed() {
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  int get totalUnreadCount {
    final allTimelineItems = _cachedTimeline.isNotEmpty
        ? _cachedTimeline
        : _buildUnifiedTimeline();
    return allTimelineItems.where((i) => !i.isRead && !i.isExpired).length;
  }

  Set<String> get _localReadNotificationIds =>
      ApiService.localReadNotificationIds;

  void _onPlanPostedNotify() {
    if (mounted) {
      _loadFeed(showLoader: false, forceRefresh: true);
    }
  }

  void _onProfileUpdateNotify() {
    if (mounted) {
      _loadFeed(showLoader: false, forceRefresh: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadFeed(showLoader: false, forceRefresh: true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionUserId = ApiService.currentUserId;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Instant frame-0 hydration from memory cache (zero loading latency)
    if (ApiService.cachedLiveFeedData != null || ApiService.cachedNotifications != null) {
      final cachedFeed = ApiService.cachedLiveFeedData;
      if (cachedFeed != null) {
        _feedItems = [
          ...List<Map<String, dynamic>>.from(cachedFeed['feed'] ?? []),
          ...List<Map<String, dynamic>>.from(cachedFeed['myRequests'] ?? []),
          ...List<Map<String, dynamic>>.from(cachedFeed['incomingRequests'] ?? []),
          ...List<Map<String, dynamic>>.from(cachedFeed['pendingPayments'] ?? []),
        ];
      }
      if (ApiService.cachedNotifications != null) {
        _notifications = ApiService.cachedNotifications!;
      }
      _cachedTimeline = _buildUnifiedTimeline();
      _isLoading = false;
    }

    _loadFeed(showLoader: _cachedTimeline.isEmpty);
    _initSocketListeners();

    // Razorpay setup (native platforms only)
    if (!kIsWeb) {
      try {
        _razorpay = Razorpay();
        _razorpay!.on(
          Razorpay.EVENT_PAYMENT_SUCCESS,
          _onLargePartyPaymentSuccess,
        );
        _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onLargePartyPaymentError);
        _razorpay!.on(
          Razorpay.EVENT_EXTERNAL_WALLET,
          _onLargePartyExternalWallet,
        );
      } catch (e) {
        debugPrint('Razorpay init error: $e');
      }
    }

    // Background sync timer every 15 seconds (sockets provide instant real-time pushes)
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _loadFeed(showLoader: false);
      }
    });

    ApiService.planPostedNotifier.addListener(_onPlanPostedNotify);
    ApiService.profileUpdateNotifier.addListener(_onProfileUpdateNotify);
    ApiService.authSessionNotifier.addListener(_onAuthSessionChanged);

    RealtimeSyncManager.instance.liveFeedNotifier.addListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.strangerMeetNotifier.addListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.partyPlanNotifier.addListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.recentPostsNotifier.addListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.globalSyncTick.addListener(
      _onRealtimeLiveFeedChanged,
    );
  }

  void _onRealtimeLiveFeedChanged() {
    if (!mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiService.planPostedNotifier.removeListener(_onPlanPostedNotify);
    ApiService.profileUpdateNotifier.removeListener(_onProfileUpdateNotify);
    ApiService.authSessionNotifier.removeListener(_onAuthSessionChanged);

    RealtimeSyncManager.instance.liveFeedNotifier.removeListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.strangerMeetNotifier.removeListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.partyPlanNotifier.removeListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.recentPostsNotifier.removeListener(
      _onRealtimeLiveFeedChanged,
    );
    RealtimeSyncManager.instance.globalSyncTick.removeListener(
      _onRealtimeLiveFeedChanged,
    );
    _disposeSocketListeners();
    _pollingTimer?.cancel();
    _pulseController.dispose();
    if (!kIsWeb) {
      try {
        _razorpay?.clear();
      } catch (e) {
        debugPrint('Razorpay clear error: $e');
      }
    }
    super.dispose();
  }

  void _initSocketListeners() {
    ApiService.addSocketListener('party_plan_created', _onPartyPlanCreated);
    ApiService.addSocketListener('party_plan_deleted', _onPartyPlanDeleted);
    ApiService.addSocketListener('post_created', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener('post_updated', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener('post_deleted', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener('venue_created', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener('venue_updated', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener('event_created', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener('event_updated', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener(
      'party_plan_reposted',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_made_public',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_guest_cancelled_prompt',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_request_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_request_received',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_request_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_request_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_request_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_relisted',
      _onPartyPlanRequestUpdated,
    );
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
    ApiService.addSocketListener(
      'party_plan_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_cancellation_declined',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_arrival_confirmed',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_reach_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_reach_prompt',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_arrival_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_arrival_window_opened',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'party_plan_ticket_generated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener('plan_unavailable', _onPlanUnavailable);
    ApiService.addSocketListener(
      'party_plan_partner_selected',
      _onPlanUnavailable,
    );
    ApiService.addSocketListener(
      'notification_created',
      _onNotificationCreated,
    );
    ApiService.addSocketListener(
      'notification_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'notification_received',
      _onNotificationCreated,
    );
    ApiService.addSocketListener('badge_updated', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener(
      'live_feed_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener('group_party_created', _onGroupPartyUpdated);
    ApiService.addSocketListener(
      'group_party_payment_success',
      _onGroupPartyUpdated,
    );
    ApiService.addSocketListener('group_party_cancelled', _onGroupPartyUpdated);
    ApiService.addSocketListener(
      'large_party_status_update',
      _onGroupPartyUpdated,
    );
    ApiService.addSocketListener(
      'large_party_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'large_party_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'large_party_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'large_party_refund_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'group_party_status_update',
      _onGroupPartyUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_joiner_joined',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_host_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_joiner_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_arrival_confirmed',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_started',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_duration_extended',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_host_confirmed_ended',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_admin_confirmed_ended',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_settled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_status_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_host_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_host_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_host_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_member_refund_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'strangers_meet_refund_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'upcoming_night_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'upcoming_night_status_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'upcoming_night_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'upcoming_night_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'upcoming_night_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'upcoming_night_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'partner_request_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'partner_request_received',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'partner_request_accepted',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'partner_request_declined',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'partner_request_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener('wallet_updated', _onPartyPlanRequestUpdated);
    ApiService.addSocketListener(
      'wallet_refund_processed',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'feed_refresh_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.addSocketListener(
      'notifications_read_all',
      _onNotificationsReadAll,
    );
  }

  void _disposeSocketListeners() {
    ApiService.removeSocketListener('party_plan_created', _onPartyPlanCreated);
    ApiService.removeSocketListener('party_plan_deleted', _onPartyPlanDeleted);
    ApiService.removeSocketListener(
      'party_plan_reposted',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_made_public',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_guest_cancelled_prompt',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_cancellation_declined',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_reach_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_reach_prompt',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_arrival_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_request_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_request_received',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_request_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_request_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_request_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_relisted',
      _onPartyPlanRequestUpdated,
    );
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
    ApiService.removeSocketListener(
      'party_plan_arrival_confirmed',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_arrival_window_opened',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'party_plan_ticket_generated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener('plan_unavailable', _onPlanUnavailable);
    ApiService.removeSocketListener(
      'party_plan_partner_selected',
      _onPlanUnavailable,
    );
    ApiService.removeSocketListener(
      'notification_created',
      _onNotificationCreated,
    );
    ApiService.removeSocketListener(
      'notification_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'notification_received',
      _onNotificationCreated,
    );
    ApiService.removeSocketListener(
      'badge_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'live_feed_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'venue_booking_status_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'group_party_created',
      _onGroupPartyUpdated,
    );
    ApiService.removeSocketListener(
      'group_party_payment_success',
      _onGroupPartyUpdated,
    );
    ApiService.removeSocketListener(
      'group_party_cancelled',
      _onGroupPartyUpdated,
    );
    ApiService.removeSocketListener(
      'large_party_status_update',
      _onGroupPartyUpdated,
    );
    ApiService.removeSocketListener(
      'large_party_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'large_party_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'large_party_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'large_party_refund_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'group_party_status_update',
      _onGroupPartyUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_joiner_joined',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_host_paid',
      _onPartyPlanHostPaid,
    );
    ApiService.removeSocketListener(
      'strangers_meet_joiner_paid',
      _onPartyPlanJoinerPaid,
    );
    ApiService.removeSocketListener(
      'strangers_meet_arrival_confirmed',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_started',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_duration_extended',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_host_confirmed_ended',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_admin_confirmed_ended',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_settled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_status_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_host_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_host_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_host_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_member_refund_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'strangers_meet_refund_paid',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'upcoming_night_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'upcoming_night_status_update',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'upcoming_night_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'upcoming_night_cancellation_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'upcoming_night_cancellation_approved',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'upcoming_night_cancellation_rejected',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'partner_request_created',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'partner_request_received',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'partner_request_accepted',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'partner_request_declined',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'partner_request_cancelled',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'wallet_updated',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'wallet_refund_processed',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'feed_refresh_requested',
      _onPartyPlanRequestUpdated,
    );
    ApiService.removeSocketListener(
      'notifications_read_all',
      _onNotificationsReadAll,
    );
  }

  bool _hasPendingRefetch = false;

  void _onNotificationsReadAll(dynamic data) {
    if (!mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onPartyPlanRequestUpdated(dynamic data) {
    if (!mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onNotificationCreated(dynamic data) {
    if (!mounted || !context.mounted) return;
    if (data is Map) {
      final rawMap = Map<String, dynamic>.from(data);
      final notifMap = rawMap['notification'] is Map
          ? Map<String, dynamic>.from(rawMap['notification'])
          : rawMap;
      final recipientId =
          (notifMap['recipientUserId'] ??
                  notifMap['recipientId'] ??
                  notifMap['userId'] ??
                  '')
              .toString();
      final currentUid = ApiService.currentUserId ?? '';
      if (recipientId.isNotEmpty &&
          currentUid.isNotEmpty &&
          recipientId != currentUid) {
        return;
      }
      _loadFeed(showLoader: false, forceRefresh: true);
      _loadGroupPartyBookings();
      TopNotificationBanner.show(
        title: notifMap['title'] ?? 'New Notification 🔔',
        body: notifMap['body'] ?? '',
        data: notifMap['data'] is Map
            ? Map<String, dynamic>.from(notifMap['data'])
            : (notifMap['metadata'] is Map
                  ? Map<String, dynamic>.from(notifMap['metadata'])
                  : notifMap),
      );
    } else {
      _loadFeed(showLoader: false, forceRefresh: true);
      _loadGroupPartyBookings();
    }
  }

  void _onGroupPartyUpdated(dynamic data) {
    if (!mounted || !context.mounted) return;
    if (data is Map) {
      final notifMap = Map<String, dynamic>.from(data);
      final recipientId =
          (notifMap['recipientUserId'] ??
                  notifMap['recipientId'] ??
                  notifMap['userId'] ??
                  '')
              .toString();
      final currentUid = ApiService.currentUserId ?? '';
      if (recipientId.isNotEmpty &&
          currentUid.isNotEmpty &&
          recipientId != currentUid) {
        return;
      }
      _loadFeed(showLoader: false, forceRefresh: true);
      _loadGroupPartyBookings();
      TopNotificationBanner.show(
        title: notifMap['title'] ?? 'Group Party Updated 🎉',
        body:
            notifMap['body'] ??
            notifMap['message'] ??
            'Your group party booking status has been updated.',
        data: notifMap['data'] is Map
            ? Map<String, dynamic>.from(notifMap['data'])
            : null,
      );
    } else {
      _loadFeed(showLoader: false, forceRefresh: true);
      _loadGroupPartyBookings();
    }
  }

  void _onPartyPlanCreated(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onPartyPlanDeleted(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onPartyPlanRequestAccepted(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onPartyPlanMatchSuccess(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onPartyPlanHostPaid(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onPartyPlanJoinerPaid(dynamic data) {
    if (!mounted || !context.mounted) return;
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  void _onPlanUnavailable(dynamic data) {
    if (!mounted || !context.mounted) return;
    if (data is Map) {
      final pId = (data['planId'] ?? data['partyPlanId'] ?? data['id'])
          ?.toString();
      if (pId != null && pId.isNotEmpty) {
        ApiService.markPartyPlanAsCancelledLocal(pId);
      }
    }
    _loadFeed(showLoader: false, forceRefresh: true);
  }

  Future<void> _loadGroupPartyBookings() async {
    final requestUserId = _sessionUserId;
    try {
      final list = await ApiService.fetchMyLargePartyBookings();
      if (mounted &&
          requestUserId == ApiService.currentUserId &&
          requestUserId == _sessionUserId) {
        setState(() {
          _largePartyBookings = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading group party bookings: $e');
    }
  }

  bool _hasPendingForceRefresh = false;

  Future<void> _loadFeed({
    bool showLoader = true,
    bool forceRefresh = false,
  }) async {
    final requestUserId = _sessionUserId;
    if (_isFetchingFeed) {
      _hasPendingRefetch = true;
      if (forceRefresh) _hasPendingForceRefresh = true;
      return;
    }
    _isFetchingFeed = true;

    if (showLoader && _feedItems.isEmpty && _notifications.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      await ApiService.loadLocalReadIds();
      final responses = await Future.wait([
        ApiService.fetchLiveFeedData(forceRefresh: forceRefresh),
        ApiService.fetchNotifications(forceRefresh: forceRefresh),
        ApiService.fetchMyLargePartyBookings(forceRefresh: forceRefresh),
        ApiService.fetchBookings(forceRefresh: forceRefresh),
      ]);

      final data = responses[0] as Map<String, dynamic>;
      final notifs = responses[1] as List<Map<String, dynamic>>;
      final largeParties = responses[2] as List<Map<String, dynamic>>;
      final rawBookings = (responses[3] as List<dynamic>?) ?? [];
      final userBookings = rawBookings
          .whereType<Map>()
          .map((b) => Map<String, dynamic>.from(b))
          .toList();

      List<Map<String, dynamic>> combined = [
        ...List<Map<String, dynamic>>.from(data['feed'] ?? []),
        ...List<Map<String, dynamic>>.from(data['myRequests'] ?? []),
        ...List<Map<String, dynamic>>.from(data['incomingRequests'] ?? []),
        ...List<Map<String, dynamic>>.from(data['pendingPayments'] ?? []),
      ];

      if (mounted &&
          requestUserId == ApiService.currentUserId &&
          requestUserId == _sessionUserId) {
        _feedItems = combined;
        _largePartyBookings = largeParties;
        _userBookings = userBookings;
        _notifications = notifs.map((n) {
          final nId = n['id']?.toString() ?? '';
          if (_localReadNotificationIds.contains(nId) ||
              ApiService.localReadRequestIds.contains(nId)) {
            return {...n, 'read': true, 'isRead': true};
          }
          return n;
        }).toList();
        _cachedTimeline = _buildUnifiedTimeline();
        setState(() {
          _isLoading = false;
        });
        widget.onCountChanged?.call();
      }
    } catch (e) {
      debugPrint('Error loading live feed: $e');
      if (mounted && requestUserId == _sessionUserId) {
        setState(() => _isLoading = false);
      }
    } finally {
      _isFetchingFeed = false;
      if (_hasPendingRefetch && mounted) {
        final pendingForce = _hasPendingForceRefresh;
        _hasPendingRefetch = false;
        _hasPendingForceRefresh = false;
        _loadFeed(showLoader: false, forceRefresh: pendingForce);
      }
    }
  }

  void _onAuthSessionChanged() {
    if (!mounted) return;
    _sessionUserId = ApiService.currentUserId;
    setState(() {
      _feedItems = [];
      _notifications = [];
      _largePartyBookings = [];
      _userBookings = [];
      _cachedTimeline = [];
      _isLoading = _sessionUserId != null;
    });
    if (_sessionUserId != null) {
      refreshFeed();
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    final allItems = _cachedTimeline.isNotEmpty
        ? _cachedTimeline
        : _buildUnifiedTimeline();
    for (final item in allItems) {
      if (item.badgeText == 'ACTION REQUIRED' ||
          item.badgeText == 'INVITE' ||
          item.badgeText == 'NEW REQUEST' ||
          item.priority == 'CRITICAL') {
        continue; // Active action required items keep their action badge
      }
      final rawId =
          item.rawData['id']?.toString() ??
          item.id.replaceAll(
            RegExp(r'^(gp_|pp_|sm_|venue_booking_timeline_)'),
            '',
          );
      if (rawId.isNotEmpty) {
        ApiService.localReadRequestIds.add(rawId);
        ApiService.localReadRequestIds.add(item.id);
        ApiService.localReadNotificationIds.add(rawId);
        ApiService.localReadNotificationIds.add(item.id);
      }
    }
    for (final n in _notifications) {
      final nId = n['id']?.toString() ?? '';
      if (nId.isNotEmpty) {
        ApiService.localReadNotificationIds.add(nId);
      }
    }

    // ── Instant optimistic local update (0ms UI delay!) ──────────────
    if (mounted) {
      _notifications = _notifications.map((n) {
        return {...n, 'read': true, 'isRead': true};
      }).toList();
      _cachedTimeline = _buildUnifiedTimeline();
      setState(() {});
      widget.onCountChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications marked as read ✓'),
          backgroundColor: LunaraTheme.electricViolet,
          duration: Duration(seconds: 2),
        ),
      );
    }

    // ── Persist to storage & server asynchronously in background ──────
    unawaited(() async {
      try {
        await Future.wait([
          ApiService.saveLocalReadRequestIds(),
          ApiService.saveLocalReadNotificationIds(),
          ApiService.markAllNotificationsAsRead(),
          ApiService.clearAllNotifications(),
        ]);
      } catch (e) {
        debugPrint('Background markAllNotificationsAsRead error: $e');
      }
    }());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Instant Optimistic State Mutators
  // ─────────────────────────────────────────────────────────────────────────────
  void _optimisticallyUpdatePartyPlanRequest(String reqId, String newStatus) {
    final cleanReq = ApiService.cleanBookingId(reqId);
    for (int i = 0; i < _feedItems.length; i++) {
      final f = _feedItems[i];
      final rId = (f['id'] ?? f['requestId'] ?? f['data']?['id'] ?? '')
          .toString();
      final pId = (f['planId'] ?? f['partyPlanId'] ?? '').toString();
      final cleanF = ApiService.cleanBookingId(rId);
      final cleanP = ApiService.cleanBookingId(pId);

      if (rId == reqId ||
          cleanF == cleanReq ||
          pId == reqId ||
          cleanP == cleanReq) {
        final updated = Map<String, dynamic>.from(f);
        updated['status'] = newStatus;
        updated['requestStatus'] = newStatus;
        if (newStatus == 'cancelled' || newStatus == 'rejected' || newStatus == 'withdrawn') {
          updated['lifecycleStatus'] = newStatus == 'cancelled' ? 'cancelled' : updated['lifecycleStatus'];
          updated['isCancelled'] = newStatus == 'cancelled';
          if (pId.isNotEmpty) {
            ApiService.markPartyPlanAsCancelledLocal(pId);
          } else if (rId.isNotEmpty) {
            ApiService.markPartyPlanAsCancelledLocal(rId);
          }
        } else if (newStatus == 'accepted') {
          updated['lifecycleStatus'] = 'payment_pending';
          updated['matchedRequestId'] = reqId;
          if (pId.isNotEmpty) {
            ApiService.markPartyPlanAsRequestedLocal(pId, {'id': reqId, 'planId': pId, 'status': 'accepted'});
          }
        }
        if (updated['myRequest'] is Map) {
          updated['myRequest'] = {
            ...Map<String, dynamic>.from(updated['myRequest'] as Map),
            'status': newStatus,
          };
        }
        if (updated['pendingIncomingRequests'] is List) {
          final reqs = List<Map<String, dynamic>>.from(
            updated['pendingIncomingRequests'],
          );
          reqs.removeWhere(
            (r) =>
                (r['id']?.toString() == reqId ||
                ApiService.cleanBookingId(r['id']?.toString() ?? '') ==
                    cleanReq),
          );
          updated['pendingIncomingRequests'] = reqs;
        }
        _feedItems[i] = updated;
      }
    }
    _cachedTimeline = _buildUnifiedTimeline();
    if (mounted) setState(() {});
    widget.onCountChanged?.call();
  }

  void _optimisticallyUpdatePartyPlanInvite(String reqId, String newStatus) {
    final cleanReq = ApiService.cleanBookingId(reqId);
    for (int i = 0; i < _feedItems.length; i++) {
      final f = _feedItems[i];
      final rId =
          (f['id'] ?? f['requestId'] ?? f['inviteId'] ?? f['data']?['id'] ?? '')
              .toString();
      final pId = (f['planId'] ?? f['partyPlanId'] ?? '').toString();
      final cleanF = ApiService.cleanBookingId(rId);
      final cleanP = ApiService.cleanBookingId(pId);
      if (rId == reqId ||
          cleanF == cleanReq ||
          pId == reqId ||
          cleanP == cleanReq) {
        final updated = Map<String, dynamic>.from(f);
        updated['status'] = newStatus;
        updated['inviteStatus'] = newStatus;
        if (updated['myRequest'] is Map) {
          updated['myRequest'] = {
            ...Map<String, dynamic>.from(updated['myRequest'] as Map),
            'status': newStatus,
          };
        }
        _feedItems[i] = updated;
      }
    }
    _cachedTimeline = _buildUnifiedTimeline();
    if (mounted) setState(() {});
    widget.onCountChanged?.call();
  }

  void _optimisticallyUpdateStrangersMeetJoinRequest(
    String meetId,
    String joinerId,
    String newStatus,
  ) {
    final cleanMeet = ApiService.cleanBookingId(meetId);
    final cleanJoiner = ApiService.cleanBookingId(joinerId);
    for (int i = 0; i < _feedItems.length; i++) {
      final f = _feedItems[i];
      final mId =
          (f['meetId'] ??
                  f['strangersMeetId'] ??
                  f['data']?['meetId'] ??
                  f['data']?['strangersMeetId'] ??
                  f['id'] ??
                  '')
              .toString();
      final jId = (f['joinerId'] ?? f['id'] ?? f['data']?['joinerId'] ?? '')
          .toString();
      final cleanM = ApiService.cleanBookingId(mId);
      final cleanJ = ApiService.cleanBookingId(jId);

      if ((cleanM == cleanMeet || cleanMeet.isEmpty) &&
          (cleanJ == cleanJoiner || jId == joinerId)) {
        final updated = Map<String, dynamic>.from(f);
        updated['status'] = newStatus;
        updated['joinStatus'] = newStatus;
        _feedItems[i] = updated;
      } else if (cleanM == cleanMeet || mId == meetId) {
        final updated = Map<String, dynamic>.from(f);
        if (updated['pendingIncomingRequests'] is List) {
          final list = List<Map<String, dynamic>>.from(
            updated['pendingIncomingRequests'],
          );
          list.removeWhere(
            (r) =>
                r['id']?.toString() == joinerId ||
                r['joinerId']?.toString() == joinerId,
          );
          updated['pendingIncomingRequests'] = list;
        }
        _feedItems[i] = updated;
      }
    }
    _cachedTimeline = _buildUnifiedTimeline();
    if (mounted) setState(() {});
    widget.onCountChanged?.call();
  }

  void _optimisticallyUpdateNightPartnerRequest(
    String matchId,
    String newStatus,
  ) {
    for (int i = 0; i < _feedItems.length; i++) {
      final f = _feedItems[i];
      final id = (f['id'] ?? f['matchId'] ?? f['requestId'] ?? '').toString();
      if (id == matchId) {
        _feedItems[i] = {
          ...f,
          'status': newStatus,
          'stage': newStatus == 'accepted' ? 'WAITING_FOR_PAYMENT' : 'DECLINED',
        };
      }
    }
    for (int i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      final id = (n['id'] ?? n['entityId'] ?? n['data']?['matchId'] ?? '')
          .toString();
      if (id == matchId || id.contains(matchId)) {
        _notifications[i] = {
          ...n,
          'status': newStatus,
          'stage': newStatus == 'accepted' ? 'WAITING_FOR_PAYMENT' : 'DECLINED',
        };
      }
    }
    _cachedTimeline = _buildUnifiedTimeline();
    if (mounted) setState(() {});
    widget.onCountChanged?.call();
  }

  void _optimisticallyMarkBookingCancelled(
    String rawBookingId, {
    double? refundAmount,
    int? refundPercentage,
  }) {
    final cleanId = ApiService.cleanBookingId(rawBookingId);
    if (cleanId.isEmpty) return;

    for (int i = 0; i < _userBookings.length; i++) {
      final bId = ApiService.cleanBookingId(
        (_userBookings[i]['id'] ?? _userBookings[i]['bookingId'] ?? '')
            .toString(),
      );
      if (bId == cleanId) {
        _userBookings[i] = {
          ..._userBookings[i],
          'status': 'cancelled',
          'bookingStatus': 'cancelled',
          'paymentStatus': 'refunded',
          if (refundAmount != null && refundAmount > 0)
            'refundAmount': refundAmount,
          'refundPercentage': ?refundPercentage,
        };
      }
    }

    for (int i = 0; i < _largePartyBookings.length; i++) {
      final bId = ApiService.cleanBookingId(
        (_largePartyBookings[i]['id'] ??
                _largePartyBookings[i]['bookingId'] ??
                '')
            .toString(),
      );
      if (bId == cleanId) {
        _largePartyBookings[i] = {
          ..._largePartyBookings[i],
          'status': 'cancelled',
          'overallStatus': 'cancelled',
          'cancelStatus': 'COMPLETED',
          'paymentStatus': 'refunded',
          if (refundAmount != null && refundAmount > 0)
            'refundAmount': refundAmount,
          'refundPercentage': ?refundPercentage,
        };
      }
    }

    for (int i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      final nId = ApiService.cleanBookingId((n['id'] ?? '').toString());
      final entityId = ApiService.cleanBookingId(
        (n['entityId'] ?? n['data']?['bookingId'] ?? '').toString(),
      );
      if (nId.contains(cleanId) || entityId == cleanId) {
        _notifications[i] = {
          ...n,
          'status': 'cancelled',
          'paymentStatus': 'refunded',
          if (refundAmount != null && refundAmount > 0)
            'refundAmount': refundAmount,
          'refundPercentage': ?refundPercentage,
          'data': {
            if (n['data'] is Map) ...(n['data'] as Map<String, dynamic>),
            'status': 'cancelled',
            'paymentStatus': 'refunded',
            if (refundAmount != null && refundAmount > 0)
              'refundAmount': refundAmount,
            'refundPercentage': ?refundPercentage,
          },
        };
      }
    }

    for (int i = 0; i < _feedItems.length; i++) {
      final f = _feedItems[i];
      final fId = ApiService.cleanBookingId(
        (f['id'] ?? f['bookingId'] ?? '').toString(),
      );
      if (fId == cleanId) {
        _feedItems[i] = {
          ...f,
          'status': 'cancelled',
          'paymentStatus': 'refunded',
          if (refundAmount != null && refundAmount > 0)
            'refundAmount': refundAmount,
          'refundPercentage': ?refundPercentage,
        };
      }
    }

    _cachedTimeline = _buildUnifiedTimeline();
    if (mounted) setState(() {});
    widget.onCountChanged?.call();
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
    debugPrint(
      'Large Party Payment Error: ${response.code} - ${response.message}',
    );
    _pendingLargePartyBookingId = null;
    if (mounted) {
      final isCancelled =
          response.code == Razorpay.PAYMENT_CANCELLED ||
          response.code == 2 ||
          (response.message != null &&
              (response.message!.toLowerCase().contains('cancel') ||
                  response.message!.toLowerCase().contains('back')));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCancelled
                ? 'Payment cancelled. You can complete your booking payment anytime.'
                : 'Payment failed: ${response.message ?? "Please try again"}',
          ),
          backgroundColor: isCancelled ? Colors.black87 : Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _onLargePartyExternalWallet(ExternalWalletResponse response) {
    debugPrint('External wallet selected: ${response.walletName}');
  }

  Future<void> _handleLargePartySuccess({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    final bookingId = _pendingLargePartyBookingId;
    _pendingLargePartyBookingId = null;
    if (bookingId == null || bookingId.isEmpty) return;

    try {
      final verified = await ApiService.verifyLargePartyPayment(
        bookingId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );
      if (!mounted || !context.mounted) return;
      if (verified) {
        _optimisticallyUpdateLargePartyPayment(bookingId: bookingId);
        await _loadGroupPartyBookings();
        _loadFeed(showLoader: false);
        TopNotificationBanner.show(
          title: 'Group Party Confirmed! 🎉',
          body:
              'Your payment was verified successfully. Tap to view your ticket!',
          data: {'type': 'group_party_confirmed', 'partyId': bookingId},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 Group Party Paid successfully! Ticket is confirmed.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('_handleLargePartySuccess error: $e');
    }
  }

  Future<void> _initiateLargePartyPayment(Map<String, dynamic> booking) async {
    final rawBookingId =
        booking['bookingId']?.toString() ??
        booking['metadata']?['bookingId']?.toString() ??
        booking['metadata']?['partyId']?.toString() ??
        booking['entityId']?.toString() ??
        booking['partyId']?.toString() ??
        booking['groupPartyId']?.toString() ??
        booking['data']?['partyId']?.toString() ??
        booking['data']?['bookingId']?.toString() ??
        booking['id']?.toString() ??
        '';
    final bookingId = ApiService.cleanBookingId(rawBookingId);
    if (bookingId.isEmpty) return;

    final trackingId = bookingId.isNotEmpty ? bookingId : rawBookingId;
    if (_processingPaymentBookingId != null) return;
    setState(() => _processingPaymentBookingId = trackingId);

    try {
      final venueName =
          booking['venue']?['name'] ?? booking['venueName'] ?? 'Venue';
      final rawAmount =
          booking['totalAmount'] ??
          booking['adminPaymentAmount'] ??
          booking['amount'] ??
          booking['price'] ??
          1999.0;
      final double amount = (rawAmount is num)
          ? rawAmount.toDouble()
          : (double.tryParse(rawAmount.toString()) ?? 1999.0);

      final bool? sheetSuccess = await SmartCheckoutSheet.show(
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
            final transactionId =
                res['data']?['transactionId']?.toString() ?? 'wallet';
            final confirmRes = await ApiService.verifyLargePartyPayment(
              bookingId,
              razorpayOrderId: 'order_mock_wallet',
              razorpayPaymentId: 'wallet_$transactionId',
              razorpaySignature: 'mock_signature',
            );
            if (confirmRes) {
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
            final razorpayKey =
                result['razorpayKeyId']?.toString() ??
                orderData['key']?.toString() ??
                '';
            final orderId =
                orderData['razorpayOrderId']?.toString() ??
                orderData['id']?.toString() ??
                '';
            final num amountInPaise =
                orderData['amount'] ?? ((amount * 100).toInt());

            if (kIsWeb || _razorpay == null) {
              final bool? shouldConfirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1035),
                  title: const Text(
                    'Direct Payment Gateway',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Text(
                    'Simulate Razorpay payment of ₹${amount.toInt()} for Group Party at $venueName?',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                      ),
                      child: const Text(
                        'Confirm Pay',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );

              if (shouldConfirm == true) {
                final success = await ApiService.verifyLargePartyPayment(
                  bookingId,
                  razorpayOrderId: orderId.isNotEmpty
                      ? orderId
                      : 'order_mock_${DateTime.now().millisecondsSinceEpoch}',
                  razorpayPaymentId:
                      'mock_payment_${DateTime.now().millisecondsSinceEpoch}',
                  razorpaySignature: 'mock_signature',
                );
                if (success && mounted) {
                  await _loadGroupPartyBookings();
                  _loadFeed(showLoader: false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '🎉 Group Party Paid successfully! Ticket is confirmed.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                  return true;
                }
                return false;
              } else {
                _pendingLargePartyBookingId = null;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment cancelled.'),
                      backgroundColor: Colors.black87,
                    ),
                  );
                }
                return false;
              }
            }

            final effectiveKey =
                (razorpayKey.isNotEmpty && razorpayKey != 'rzp_test_123')
                ? razorpayKey
                : 'rzp_test_T1rwVokR7tFger';
            final options = {
              'key': effectiveKey,
              if (orderId.isNotEmpty && !orderId.startsWith('order_mock_'))
                'order_id': orderId,
              'amount': amountInPaise,
              'name': 'Lunara – Group Party',
              'description': 'Group Party at $venueName',
              'prefill': {
                'contact': booking['mobileNumber']?.toString() ?? '9999999999',
                'email': 'user@lunara.app',
              },
              'theme': {'color': '#7C3AED'},
            };

            try {
              _razorpay?.open(options);
              return 'gateway_launched';
            } catch (e) {
              debugPrint('Razorpay open error: $e');
              _pendingLargePartyBookingId = null;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not open payment gateway: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
              return false;
            }
          } else if (mounted) {
            _pendingLargePartyBookingId = null;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result?['message']?.toString() ??
                      'Failed to initiate payment gateway',
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
            return false;
          }
          return false;
        },
        onHybridPayment: (shortfall) async {
          _pendingLargePartyBookingId = bookingId;
          final result = await ApiService.initiateLargePartyPayment(bookingId);
          if (result != null && result['success'] == true) {
            final orderData = result['order'] ?? result['data'] ?? result;
            final razorpayKey =
                result['razorpayKeyId']?.toString() ??
                orderData['key']?.toString() ??
                '';
            final orderId =
                orderData['razorpayOrderId']?.toString() ??
                orderData['id']?.toString() ??
                '';
            final shortfallPaise = (shortfall * 100).toInt();

            if (kIsWeb || _razorpay == null) {
              final bool? shouldConfirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1035),
                  title: const Text(
                    'Smart Hybrid Payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Text(
                    'Pay shortfall of ₹${shortfall.toInt()} via Direct Gateway + remaining from wallet for Group Party at $venueName?',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                      ),
                      child: const Text(
                        'Confirm Pay',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );

              if (shouldConfirm == true) {
                await ApiService.payWithWallet(
                  amount: amount,
                  bookingId: bookingId,
                  paymentType: 'group_party',
                );
                final success = await ApiService.verifyLargePartyPayment(
                  bookingId,
                  razorpayOrderId: orderId.isNotEmpty
                      ? orderId
                      : 'order_mock_${DateTime.now().millisecondsSinceEpoch}',
                  razorpayPaymentId:
                      'mock_payment_${DateTime.now().millisecondsSinceEpoch}',
                  razorpaySignature: 'mock_signature',
                );
                if (success && mounted) {
                  await _loadGroupPartyBookings();
                  _loadFeed(showLoader: false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '🎉 Group Party Paid successfully! Ticket is confirmed.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                  return true;
                }
                return false;
              } else {
                _pendingLargePartyBookingId = null;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment cancelled.'),
                      backgroundColor: Colors.black87,
                    ),
                  );
                }
                return false;
              }
            }

            final effectiveKey =
                (razorpayKey.isNotEmpty && razorpayKey != 'rzp_test_123')
                ? razorpayKey
                : 'rzp_test_T1rwVokR7tFger';
            final options = {
              'key': effectiveKey,
              if (orderId.isNotEmpty && !orderId.startsWith('order_mock_'))
                'order_id': orderId,
              'amount': shortfallPaise,
              'name': 'Lunara – Group Party Shortfall',
              'description': 'Group Party Shortfall at $venueName',
              'prefill': {
                'contact': booking['mobileNumber']?.toString() ?? '9999999999',
                'email': 'user@lunara.app',
              },
              'theme': {'color': '#7C3AED'},
            };

            try {
              _razorpay?.open(options);
              return 'gateway_launched';
            } catch (e) {
              debugPrint('Razorpay open error: $e');
              _pendingLargePartyBookingId = null;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not open payment gateway: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
              return false;
            }
          } else if (mounted) {
            _pendingLargePartyBookingId = null;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result?['message']?.toString() ??
                      'Failed to initiate payment gateway',
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
            return false;
          }
          return false;
        },
      );

      if (sheetSuccess == true && mounted) {
        TopNotificationBanner.show(
          title: 'Group Party Confirmed! 🎉',
          body:
              'Your group party booking was paid via Smart Wallet. Ticket generated!',
          data: {'type': 'group_party_confirmed', 'partyId': bookingId},
        );
        _optimisticallyUpdateLargePartyPayment(bookingId: bookingId);
        ApiService.notifyFeedNeedsRefresh();
        await _loadGroupPartyBookings();
        _loadFeed(showLoader: false);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LargePartyTicketScreen(
                booking: booking,
                venue: booking['venue'] is Map ? booking['venue'] : {},
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[LiveFeed] Error in _initiateLargePartyPayment: $e');
    } finally {
      if (mounted) {
        setState(() => _processingPaymentBookingId = null);
      }
    }
  }

  Future<void> _initiatePendingBookingPayment(
    Map<String, dynamic> payPayload,
  ) async {
    final type = (payPayload['type'] ?? '').toString();
    final rawBookingId = (payPayload['bookingId'] ?? payPayload['id'] ?? '')
        .toString();
    final cleanBookingId = ApiService.cleanBookingId(rawBookingId);
    final planId = (payPayload['planId'] ?? '').toString();
    final groupPartyId = (payPayload['groupPartyId'] ?? '').toString();
    final venueName =
        payPayload['venueName'] ?? payPayload['venue']?['name'] ?? 'Venue';
    final rawAmount =
        payPayload['amount'] ??
        payPayload['amountDue'] ??
        payPayload['totalAmount'] ??
        payPayload['depositAmount'] ??
        1999.0;
    final double amount = (rawAmount is num)
        ? rawAmount.toDouble()
        : (double.tryParse(rawAmount.toString()) ?? 1999.0);

    if (type == 'group_party' ||
        groupPartyId.isNotEmpty ||
        (payPayload['isLargeParty'] == true) ||
        payPayload['goingMode'] == 'party_request') {
      await _initiateLargePartyPayment(payPayload);
      return;
    }

    if (type == 'party_plan' ||
        type == 'party_plan_join' ||
        planId.isNotEmpty) {
      if (planId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PartyPlanDetailScreen(plan: {'id': planId, ...payPayload}),
          ),
        );
      }
      return;
    }

    if (cleanBookingId.isEmpty) return;

    final trackingId = cleanBookingId.isNotEmpty
        ? cleanBookingId
        : rawBookingId;
    if (_processingPaymentBookingId != null) return;
    setState(() => _processingPaymentBookingId = trackingId);

    try {
      final bool? sheetSuccess = await SmartCheckoutSheet.show(
        context: context,
        title: 'Complete Booking Payment',
        subtitle: 'Reservation at $venueName',
        itemPrice: amount,
        onWalletPayment: () async {
          final res = await ApiService.payWithWallet(
            amount: amount,
            bookingId: cleanBookingId,
            paymentType: 'booking',
          );
          if (res != null && res['success'] == true) {
            final transactionId =
                res['data']?['transactionId']?.toString() ?? 'wallet';
            final confirmRes = await ApiService.payNowBooking(
              cleanBookingId,
              paymentMethod: 'wallet',
              transactionId: transactionId,
            );
            if (confirmRes != null) {
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
          await _launchRazorpayForPendingBooking(
            bookingId: cleanBookingId,
            venueName: venueName,
            amount: amount,
            mobileNumber: payPayload['mobileNumber']?.toString(),
          );
        },
        onHybridPayment: (shortfall) async {
          final walletAmount = amount - shortfall;
          if (walletAmount > 0) {
            final wRes = await ApiService.payWithWallet(
              amount: walletAmount,
              bookingId: cleanBookingId,
              paymentType: 'booking',
            );
            if (wRes == null || wRes['success'] != true) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      wRes?['message'] ?? 'Wallet deduction failed',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
              return;
            }
          }
          await _launchRazorpayForPendingBooking(
            bookingId: cleanBookingId,
            venueName: venueName,
            amount: shortfall > 0 ? shortfall : amount,
            mobileNumber: payPayload['mobileNumber']?.toString(),
            isHybrid: true,
          );
        },
      );

      if (sheetSuccess == true && mounted) {
        TopNotificationBanner.show(
          title: 'Booking Confirmed! 🎉',
          body:
              'Your booking at $venueName was paid via Smart Wallet. Ticket is ready in Ticket Pocket!',
        );
        ApiService.notifyFeedNeedsRefresh();
        _loadFeed(showLoader: false);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TicketPocketScreen()),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _processingPaymentBookingId = null);
      }
    }
  }

  Future<void> _launchRazorpayForPendingBooking({
    required String bookingId,
    required String venueName,
    required double amount,
    String? mobileNumber,
    bool isHybrid = false,
  }) async {
    final cleanBookingId = ApiService.cleanBookingId(bookingId);
    final num amountInPaise = (amount * 100).toInt();
    const razorpayKey = 'rzp_test_T1rwVokR7tFger';
    final orderId =
        'order_bk_${cleanBookingId}_${DateTime.now().millisecondsSinceEpoch}';

    // On Web or desktop: require explicit confirmation dialog (cancel aborts cleanly without confirming)
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      final bool? shouldConfirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1035),
          title: const Text(
            'Direct Payment Gateway',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Confirm payment of ₹${amount.toInt()} for booking at $venueName?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
              ),
              child: const Text(
                'Confirm Pay',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (shouldConfirm == true) {
        final confirmRes = await ApiService.payNowBooking(
          cleanBookingId,
          paymentMethod: isHybrid ? 'hybrid' : 'razorpay',
          razorpayOrderId: orderId,
          razorpayPaymentId:
              'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
          razorpaySignature: 'mock_signature',
        );
        if (confirmRes != null && mounted) {
          _loadFeed(showLoader: false);
          TopNotificationBanner.show(
            title: 'Booking Confirmed! 🎉',
            body: 'Your payment at $venueName was verified successfully.',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Booking Payment Successful!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment cancelled.'),
              backgroundColor: Colors.black87,
            ),
          );
        }
      }
      return;
    }

    // On mobile devices (Android / iOS): Open real Razorpay payment gateway
    final rzp = Razorpay();

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
      PaymentSuccessResponse response,
    ) async {
      try {
        rzp.clear();
      } catch (_) {}

      final confirmRes = await ApiService.payNowBooking(
        cleanBookingId,
        paymentMethod: isHybrid ? 'hybrid' : 'razorpay',
        razorpayOrderId: response.orderId ?? orderId,
        razorpayPaymentId: response.paymentId ?? '',
        razorpaySignature: response.signature ?? '',
      );

      if (confirmRes != null && mounted) {
        _loadFeed(showLoader: false);
        TopNotificationBanner.show(
          title: 'Booking Confirmed! 🎉',
          body:
              'Your payment at $venueName was verified successfully. Digital ticket ready!',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Booking Payment Successful! Ticket confirmed.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      try {
        rzp.clear();
      } catch (_) {}
      final isCancelled =
          response.code == Razorpay.PAYMENT_CANCELLED ||
          response.code == 2 ||
          (response.message != null &&
              (response.message!.toLowerCase().contains('cancel') ||
                  response.message!.toLowerCase().contains('back')));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCancelled
                  ? 'Payment cancelled. You can complete your booking payment anytime.'
                  : 'Payment failed: ${response.message ?? "Please try again"}',
            ),
            backgroundColor: isCancelled ? Colors.black87 : Colors.redAccent,
          ),
        );
      }
    });

    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
      try {
        rzp.clear();
      } catch (_) {}
    });

    final options = {
      'key': razorpayKey,
      'amount': amountInPaise,
      'name': 'Lunara – Booking',
      'description': 'Booking at $venueName',
      'prefill': {
        'contact':
            mobileNumber ?? ApiService.cachedCurrentUser?.phone ?? '9999999999',
        'email': ApiService.cachedCurrentUser?.email ?? 'user@lunara.app',
      },
      'theme': {'color': '#7C3AED'},
    };

    try {
      rzp.open(options);
    } catch (e) {
      debugPrint('Razorpay open error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open payment gateway: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleAcceptPartyPlan(String reqId) async {
    final actionKey = 'accept_party_$reqId';
    if (_activeActionKeys.contains(actionKey)) return;
    setState(() => _activeActionKeys.add(actionKey));

    try {
      final res = await ApiService.acceptPartyPlanRequest(reqId);
      if (res != null) {
        _optimisticallyUpdatePartyPlanRequest(reqId, 'accepted');
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request accepted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept request.'),
            backgroundColor: Colors.red,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } catch (e) {
      debugPrint('Error accepting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } finally {
      if (mounted) setState(() => _activeActionKeys.remove(actionKey));
    }
  }

  Future<void> _handleRejectPartyPlan(String reqId) async {
    final actionKey = 'reject_party_$reqId';
    if (_activeActionKeys.contains(actionKey)) return;
    setState(() => _activeActionKeys.add(actionKey));

    try {
      final success = await ApiService.rejectPartyPlanRequest(reqId);
      if (success) {
        _optimisticallyUpdatePartyPlanRequest(reqId, 'rejected');
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request declined.'),
            backgroundColor: Colors.grey,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline request.'),
            backgroundColor: Colors.red,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } catch (e) {
      debugPrint('Error rejecting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } finally {
      if (mounted) setState(() => _activeActionKeys.remove(actionKey));
    }
  }

  void _showReviewPartyPlanRequestsModal(
    Map<String, dynamic> planMap,
    List<Map<String, dynamic>> requests,
  ) {
    final venueName =
        planMap['venueName'] ?? planMap['venue']?['name'] ?? 'Venue';
    final currentUserId = ApiService.currentUserId;
    final hostId = planMap['userId']?.toString() ??
        planMap['hostId']?.toString() ??
        planMap['creatorId']?.toString();
    final bool isHost = currentUserId != null &&
        (currentUserId == hostId ||
            planMap['isHost'] == true ||
            planMap['isMyPlan'] == true);

    final bool isPrivatePlan = planMap['isPrivate'] == true ||
        planMap['visibility'] == 'private' ||
        planMap['planType'] == 'private' ||
        planMap['isPrivatePlan'] == true ||
        planMap['category'] == 'private' ||
        (planMap['selectedUsers'] is List &&
            (planMap['selectedUsers'] as List).isNotEmpty);

    final bool isPrivateInviteModal = isHost &&
        (isPrivatePlan ||
            requests.every((r) =>
                r['requestType'] == 'private_invite' || r['isInvite'] == true));

    final titleText = isPrivateInviteModal
        ? 'Privately Invited (${requests.length})'
        : 'Join Requests (${requests.length})';
    final subtitleText = isPrivateInviteModal
        ? 'Private Party Plan at $venueName'
        : 'Party Plan at $venueName';
    final headerIcon = isPrivateInviteModal
        ? Icons.mark_email_read_rounded
        : Icons.people_alt_rounded;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF13131A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0xFF2D2D3D), width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        headerIcon,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitleText,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF222230), height: 24),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  shrinkWrap: true,
                  itemCount: requests.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    final reqUser = (req['requester'] is Map)
                        ? req['requester'] as Map<String, dynamic>
                        : (req['user'] is Map
                              ? req['user'] as Map<String, dynamic>
                              : <String, dynamic>{});
                    final reqUserName =
                        '${reqUser["firstName"] ?? "User"} ${reqUser["lastName"] ?? ""}'
                            .trim();
                    final reqId = req['id']?.toString() ?? '';
                    final userBio =
                        reqUser['profile']?['bio']?.toString() ??
                        reqUser['bio']?.toString() ??
                        '';
                    final foodPref =
                        req['foodPreference']?.toString() ??
                        reqUser['foodPreference']?.toString();
                    final drinkPref =
                        req['drinkPreference']?.toString() ??
                        reqUser['drinkPreference']?.toString();

                    final bool isInvite = req['requestType'] == 'private_invite' ||
                        req['isInvite'] == true ||
                        isPrivatePlan ||
                        (planMap['selectedUsers'] is List &&
                            (planMap['selectedUsers'] as List).contains(
                                reqUser['id']?.toString() ??
                                    req['requesterId']?.toString() ??
                                    req['userId']?.toString()));

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2A),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF2A2A3C)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              LunaraProfileImage(
                                userData: reqUser,
                                radius: 24,
                                showGradientBorder: true,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reqUserName.isNotEmpty
                                          ? reqUserName
                                          : 'Lunara Member',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (userBio.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          userBio,
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if (foodPref != null || drinkPref != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Food: ${foodPref ?? "Any"} • Drink: ${drinkPref ?? "Any"}',
                                          style: const TextStyle(
                                            color: Color(0xFFA855F7),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (isHost && isInvite)
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _handleCancelMyRequest(reqId);
                                    },
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                                    label: const Text(
                                      'Cancel Private Request',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.redAccent,
                                        fontSize: 13,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0x60EF4444),
                                      ),
                                      backgroundColor: const Color(0x15EF4444),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _handleAcceptPartyPlan(reqId);
                                    },
                                    icon: const Icon(
                                      Icons.check_circle_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Approve',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF7C3AED),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _handleRejectPartyPlan(reqId);
                                    },
                                    icon: const Icon(
                                      Icons.cancel_rounded,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                                    label: const Text(
                                      'Decline',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0x40EF4444),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
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
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReviewStrangersMeetRequestsModal(
    Map<String, dynamic> meetMap,
    List<Map<String, dynamic>> requests,
  ) {
    final venueName =
        meetMap['venueName'] ?? meetMap['venue']?['name'] ?? 'Venue';
    final meetId =
        meetMap['id']?.toString() ?? meetMap['meetId']?.toString() ?? '';
    final int confirmedCount =
        int.tryParse(
          (meetMap['paidJoinersCount'] ??
                  meetMap['slotsFilled'] ??
                  meetMap['confirmedCount'] ??
                  meetMap['paymentCount'] ??
                  0)
              .toString(),
        ) ??
        0;
    final int totalCapacity =
        int.tryParse(
          (meetMap['numberOfPersons'] ?? meetMap['capacity'] ?? 0).toString(),
        ) ??
        0;
    final String subtitleCount = totalCapacity > 0
        ? 'Stranger Meet at $venueName • $confirmedCount/$totalCapacity Confirmed'
        : (confirmedCount > 0
              ? 'Stranger Meet at $venueName • $confirmedCount Confirmed'
              : 'Stranger Meet at $venueName');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF13131A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0xFF2D2D3D), width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.people_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join Requests (${requests.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitleCount,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF222230), height: 24),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  shrinkWrap: true,
                  itemCount: requests.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    final reqUser = (req['user'] is Map)
                        ? req['user'] as Map<String, dynamic>
                        : (req['requester'] is Map
                              ? req['requester'] as Map<String, dynamic>
                              : <String, dynamic>{});
                    final reqUserName =
                        '${reqUser["firstName"] ?? "User"} ${reqUser["lastName"] ?? ""}'
                            .trim();
                    final joinerId =
                        req['joinerId']?.toString() ??
                        req['id']?.toString() ??
                        req['userId']?.toString() ??
                        '';
                    final userBio =
                        reqUser['profile']?['bio']?.toString() ??
                        reqUser['bio']?.toString() ??
                        '';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2A),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF2A2A3C)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              LunaraProfileImage(
                                userData: reqUser,
                                radius: 24,
                                showGradientBorder: true,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reqUserName.isNotEmpty
                                          ? reqUserName
                                          : 'Lunara Member',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (userBio.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          userBio,
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _handleStrangersMeetJoinAction(
                                      meetId,
                                      joinerId,
                                      'accept',
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Approve',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C3AED),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _handleStrangersMeetJoinAction(
                                      meetId,
                                      joinerId,
                                      'reject',
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.cancel_rounded,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  label: const Text(
                                    'Decline',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Color(0x40EF4444),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
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
              ),
            ],
          ),
        );
      },
    );
  }

  /// Cancels the CURRENT USER's own pending join request (joiner cancels their own request).
  Future<void> _handleCancelMyRequest(String reqId) async {
    if (!OptimisticActionGuard.start('FEED_CANCEL_REQ:$reqId')) return;

    final prevFeedItems = List<Map<String, dynamic>>.from(_feedItems);
    _optimisticallyUpdatePartyPlanRequest(reqId, 'cancelled');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Request cancelled successfully.'),
        backgroundColor: Colors.grey,
      ),
    );

    try {
      bool success = await ApiService.cancelPartyPlanRequest(reqId);
      if (!success) {
        success = await ApiService.withdrawPartyPlanRequest(reqId);
      }
      if (success) {
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        _loadFeed(showLoader: false, forceRefresh: true);
      } else {
        if (mounted) {
          setState(() {
            _feedItems = prevFeedItems;
            _cachedTimeline = _buildUnifiedTimeline();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to cancel request. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error cancelling request: $e');
      if (mounted) {
        setState(() {
          _feedItems = prevFeedItems;
          _cachedTimeline = _buildUnifiedTimeline();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      OptimisticActionGuard.end('FEED_CANCEL_REQ:$reqId');
    }
  }

  /// Accept a private invite sent by the host (calls accept-invite endpoint)
  Future<void> _handleAcceptPartyPlanInvite(String reqId) async {
    final actionKey = 'accept_invite_$reqId';
    if (_activeActionKeys.contains(actionKey)) return;
    setState(() => _activeActionKeys.add(actionKey));

    try {
      final res = await ApiService.acceptPartyPlanInvite(reqId);
      if (res != null) {
        _optimisticallyUpdatePartyPlanInvite(reqId, 'accepted');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite accepted! Proceed to pay deposit.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept invite. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } catch (e) {
      debugPrint('Error accepting invite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } finally {
      if (mounted) setState(() => _activeActionKeys.remove(actionKey));
    }
  }

  Future<void> _handleStrangersMeetJoinAction(
    String meetId,
    String joinerId,
    String action,
  ) async {
    final actionKey = 'sm_join_${action}_$joinerId';
    if (_activeActionKeys.contains(actionKey)) return;
    setState(() => _activeActionKeys.add(actionKey));

    try {
      final success = await ApiService.handleStrangersMeetJoinRequest(
        meetId,
        joinerId,
        action,
      );
      if (success) {
        _optimisticallyUpdateStrangersMeetJoinRequest(
          meetId,
          joinerId,
          action == 'accept' ? 'accepted' : 'rejected',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'accept'
                  ? 'Join request accepted!'
                  : 'Join request declined.',
            ),
            backgroundColor: action == 'accept' ? Colors.green : Colors.grey,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update join request.'),
            backgroundColor: Colors.red,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
        _loadFeed(showLoader: false, forceRefresh: true);
      }
    } finally {
      if (mounted) setState(() => _activeActionKeys.remove(actionKey));
    }
  }

  Future<void> _handleStrangersMeetCancellationAction(
    String meetId,
    String cancellationId,
    String action, {
    String? rejectReason,
  }) async {
    if (!OptimisticActionGuard.start('FEED_SM_CANCEL:$meetId:$cancellationId')) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          action == 'accept'
              ? 'Cancellation approved.'
              : 'Cancellation request rejected.',
        ),
        backgroundColor: action == 'accept'
            ? const Color(0xFF10B981)
            : Colors.grey,
      ),
    );

    try {
      final result = await ApiService.respondStrangersMeetCancellation(
        meetId,
        cancellationId,
        action: action,
        rejectReason: rejectReason,
      );
      if (result['success'] == true) {
        final cleanMeet = ApiService.cleanBookingId(meetId);
        for (int i = 0; i < _feedItems.length; i++) {
          final item = _feedItems[i];
          final mId =
              (item['id'] ?? item['meetId'] ?? item['strangersMeetId'] ?? '')
                  .toString();
          if (mId == meetId || ApiService.cleanBookingId(mId) == cleanMeet) {
            final updated = Map<String, dynamic>.from(item);
            if (updated['pendingCancellationRequests'] is List) {
              final list = List<Map<String, dynamic>>.from(
                updated['pendingCancellationRequests'],
              );
              list.removeWhere(
                (c) =>
                    c['cancellationId']?.toString() == cancellationId ||
                    c['id']?.toString() == cancellationId,
              );
              updated['pendingCancellationRequests'] = list;
            }
            _feedItems[i] = updated;
          }
        }
        _cachedTimeline = _buildUnifiedTimeline();
        if (mounted) setState(() {});
        _loadFeed(showLoader: false, forceRefresh: true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'Failed to process cancellation.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        _loadFeed(showLoader: false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
        _loadFeed(showLoader: false);
      }
    } finally {
      OptimisticActionGuard.end('FEED_SM_CANCEL:$meetId:$cancellationId');
    }
  }

  void _markItemAsRead(UnifiedNotificationItem item) {
    final rawId =
        item.rawData['id']?.toString() ??
        item.id.replaceAll(RegExp(r'^(gp_|pp_|sm_)'), '');
    if (rawId.isNotEmpty) {
      ApiService.localReadRequestIds.add(rawId);
      ApiService.localReadRequestIds.add(item.id);
      ApiService.localReadNotificationIds.add(rawId);
      ApiService.localReadNotificationIds.add(item.id);
      ApiService.saveLocalReadRequestIds();
      ApiService.saveLocalReadNotificationIds();
    }
    final notifId = item.rawData['id']?.toString();
    if (notifId != null && notifId.isNotEmpty) {
      ApiService.patch(
        '/api/mobile/user/notifications/$notifId/read',
        body: {},
      );
    }
    if (mounted) {
      setState(() {});
      widget.onCountChanged?.call();
    }
  }

  void _showExpiredItemDialog(UnifiedNotificationItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.timer_off_rounded, color: Colors.grey, size: 24),
            SizedBox(width: 10),
            Text(
              'Event Expired',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.grey,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This event has passed its scheduled date or payment window. No actions can be performed.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onCardTap(UnifiedNotificationItem item) {
    _markItemAsRead(item);
    if (item.isExpired) {
      _showExpiredItemDialog(item);
      return;
    }
    final status =
        (item.rawData['status'] ?? item.rawData['paymentStatus'] ?? '')
            .toString()
            .toLowerCase();
    final category = item.category.toLowerCase();
    final pendingReqs = item.rawData['pendingIncomingRequests'];

    if (category.contains('stranger') || category.contains('meet')) {
      final meetData = item.rawData['plan'] is Map
          ? item.rawData['plan']
          : (item.rawData['meet'] is Map
                ? item.rawData['meet']
                : (item.rawData['data'] is Map
                      ? item.rawData['data']
                      : item.rawData));

      final meetId =
          meetData['id']?.toString() ??
          meetData['requestId']?.toString() ??
          meetData['meetId']?.toString() ??
          item.rawData['id']?.toString() ??
          '';

      final Map<String, dynamic> postMap = Map<String, dynamic>.from(meetData);
      postMap['type'] = 'strangers_meet';
      postMap['id'] = meetId;
      if (item.rawData['venue'] is Map) {
        postMap['venue'] = item.rawData['venue'];
      }
      if (item.rawData['venueName'] != null) {
        postMap['venueName'] = item.rawData['venueName'];
      }
      if (item.rawData['venueImage'] != null) {
        postMap['venueImage'] = item.rawData['venueImage'];
      }
      if (item.rawData['venueImageUrl'] != null) {
        postMap['venueImageUrl'] = item.rawData['venueImageUrl'];
      }
      if (item.rawData['user'] is Map) postMap['user'] = item.rawData['user'];
      if (item.rawData['host'] is Map) postMap['host'] = item.rawData['host'];

      final Map<String, dynamic>? venueMap = (postMap['venue'] is Map)
          ? Map<String, dynamic>.from(postMap['venue'])
          : (item.rawData['venue'] is Map
                ? Map<String, dynamic>.from(item.rawData['venue'])
                : null);

      try {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(post: postMap, venue: venueMap),
          ),
        ).then((_) => _loadFeed());
      } catch (e) {
        debugPrint('Error opening Strangers Meet detail screen: $e');
      }
      return;
    } else if (category.contains('booking') || category.contains('group')) {
      final rawDataMap = Map<String, dynamic>.from(item.rawData);
      final bookingData = Map<String, dynamic>.from(
        rawDataMap['booking'] is Map ? rawDataMap['booking'] : rawDataMap,
      );
      final rawSt =
          bookingData['startTime'] ??
          bookingData['time'] ??
          bookingData['bookingTime'] ??
          rawDataMap['startTime'] ??
          rawDataMap['time'] ??
          rawDataMap['bookingTime'];
      if (rawSt != null && rawSt.toString().trim().isNotEmpty) {
        String cleanSt = rawSt.toString().trim();
        if (!cleanSt.toUpperCase().contains('AM') &&
            !cleanSt.toUpperCase().contains('PM')) {
          final parts = cleanSt.split(':');
          if (parts.isNotEmpty) {
            int h = int.tryParse(parts[0].trim()) ?? 0;
            int m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
            final ampm = h >= 12 ? 'PM' : 'AM';
            final dh = h % 12 == 0 ? 12 : h % 12;
            cleanSt = '$dh:${m.toString().padLeft(2, '0')} $ampm';
          }
        }
        bookingData['startTime'] = cleanSt;
      }
      final venueMap = (bookingData['venue'] is Map)
          ? bookingData['venue'] as Map<dynamic, dynamic>
          : {
              'name': bookingData['venueName'] ?? 'Venue',
              'id': bookingData['venueId'],
            };
      final dynamic rawLargeGuests =
          bookingData['numberOfGuests'] ??
          bookingData['guestCount'] ??
          bookingData['numberOfFriends'] ??
          0;
      final int gcInt = rawLargeGuests is num
          ? rawLargeGuests.toInt()
          : (int.tryParse(rawLargeGuests.toString()) ?? 0);
      final bool isLarge =
          gcInt > 20 ||
          bookingData['isLargePartyRequest'] == true ||
          bookingData['goingMode'] == 'party_request' ||
          category.contains('large');

      if (status == 'confirmed' || status == 'paid') {
        if (!isLarge) {
          final dynamic rawTicketGuests =
              bookingData['numberOfGuests'] ?? bookingData['guestCount'] ?? 1;
          final int guestsCount = rawTicketGuests is num
              ? rawTicketGuests.toInt()
              : (int.tryParse(rawTicketGuests.toString()) ?? 1);
          final bool isSolo = guestsCount <= 1;
          final dynamic rawAmt =
              bookingData['totalAmount'] ?? bookingData['amount'] ?? 0;
          final double amtVal = rawAmt is num
              ? rawAmt.toDouble()
              : (double.tryParse(rawAmt.toString()) ?? 0.0);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DigitalTicketScreen(
                venue: venueMap,
                date: bookingData['bookingDate']?.toString(),
                time: bookingData['startTime']?.toString(),
                table: isSolo ? 'Solo Entry' : 'Standard Table',
                guests: guestsCount.toString(),
                package: isSolo ? 'Solo Entry' : 'Standard Table',
                totalPrice: amtVal > 0
                    ? '₹${amtVal.toStringAsFixed(0)}'
                    : 'FREE (₹0)',
                ticketId:
                    (bookingData['ticketCode'] ?? bookingData['id'] ?? item.id)
                        ?.toString(),
                ticketUrl: bookingData['ticketUrl']?.toString(),
                status: 'CONFIRMED',
                booking: bookingData,
                user: ApiService.cachedCurrentUser,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LargePartyTicketScreen(booking: bookingData, venue: venueMap),
            ),
          );
        }
      } else if (status == 'approved' || status == 'pending') {
        if (!isLarge || status == 'approved') {
          _initiateLargePartyPayment(bookingData);
        }
      }
    } else if (category.contains('party') || category.contains('plan')) {
      final planData = item.rawData['plan'] is Map
          ? item.rawData['plan']
          : item.rawData;
      if (pendingReqs is List && pendingReqs.length > 1) {
        _showReviewPartyPlanRequestsModal(
          Map<String, dynamic>.from(planData),
          pendingReqs.cast<Map<String, dynamic>>(),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PartyPlanDetailScreen(plan: Map<String, dynamic>.from(planData)),
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

  DateTime? _parseEventDateTime(dynamic rawDate, [dynamic rawTime]) {
    if (rawDate == null) return null;
    try {
      final dateStr = rawDate.toString().trim();
      if (dateStr.isEmpty) return null;

      final timeStr = (rawTime ?? '').toString().trim();

      DateTime? baseDt = DateTime.tryParse(dateStr)?.toLocal();
      if (baseDt == null) {
        final ymdRegex = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})');
        final match = ymdRegex.firstMatch(dateStr);
        if (match != null) {
          final year = int.parse(match.group(1)!);
          final month = int.parse(match.group(2)!);
          final day = int.parse(match.group(3)!);
          baseDt = DateTime(year, month, day);
        } else {
          return null;
        }
      }

      if (timeStr.isNotEmpty) {
        final tp = _parseTimeComponent(timeStr);
        return DateTime(baseDt.year, baseDt.month, baseDt.day, tp[0], tp[1]);
      }

      if (baseDt.hour == 5 && baseDt.minute == 30 && dateStr.endsWith('Z')) {
        return DateTime(baseDt.year, baseDt.month, baseDt.day, 0, 0);
      }

      return baseDt;
    } catch (_) {
      return null;
    }
  }

  List<int> _parseTimeComponent(String timeStr) {
    int hour = 0; // default 12:00 AM
    int minute = 0;
    if (timeStr.isNotEmpty) {
      final cleanTime = timeStr.toUpperCase().trim();
      if (cleanTime.contains('AM') || cleanTime.contains('PM')) {
        final isPm = cleanTime.contains('PM');
        final timeOnly = cleanTime
            .replaceAll('AM', '')
            .replaceAll('PM', '')
            .trim();
        final parts = timeOnly.split(':');
        if (parts.isNotEmpty) {
          int h = int.tryParse(parts[0]) ?? 0;
          int m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          if (isPm && h < 12) h += 12;
          if (!isPm && h == 12) h = 0;
          hour = h;
          minute = m;
        }
      } else {
        final parts = cleanTime.split(':');
        if (parts.isNotEmpty) {
          hour = int.tryParse(parts[0]) ?? 0;
          minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
        }
      }
    }
    return [hour, minute];
  }

  static String? _extractUserPhoto(dynamic source) {
    if (source == null) return null;
    if (source is String) {
      final s = source.trim();
      if (s.isNotEmpty && s != 'null' && s != 'undefined') return s;
      return null;
    }
    if (source is Map) {
      final candidates = [
        source['profilePhotoUrl'],
        source['profileImageUrl'],
        source['photoUrl'],
        source['profilePhoto'],
        source['hostProfilePhotoUrl'],
        source['hostPhotoUrl'],
        source['hostPhoto'],
        source['hostImage'],
        source['creatorPhoto'],
        source['userPhotoUrl'],
        source['userPhoto'],
        source['senderImage'],
        source['senderPhoto'],
        source['imageUrl'],
        source['image'],
        source['photo'],
        source['avatar'],
        source['avatarUrl'],
        source['userAvatar'],
      ];
      for (final c in candidates) {
        if (c != null) {
          final s = c.toString().trim();
          if (s.isNotEmpty && s != 'null' && s != 'undefined') return s;
        }
      }
      if (source['photos'] is List && (source['photos'] as List).isNotEmpty) {
        final p = (source['photos'] as List).first;
        final pUrl = (p is Map) ? (p['url'] ?? p['filePath']) : p?.toString();
        if (pUrl != null) {
          final s = pUrl.toString().trim();
          if (s.isNotEmpty && s != 'null' && s != 'undefined') return s;
        }
      }
      if (source['images'] is List && (source['images'] as List).isNotEmpty) {
        final img = (source['images'] as List).first;
        final imgUrl = (img is Map)
            ? (img['url'] ?? img['filePath'])
            : img?.toString();
        if (imgUrl != null) {
          final s = imgUrl.toString().trim();
          if (s.isNotEmpty && s != 'null' && s != 'undefined') return s;
        }
      }
    }
    return null;
  }

  static String? _extractVenuePhoto(dynamic venue) {
    if (venue == null) return null;
    if (venue is String) {
      final s = venue.trim();
      if (s.isNotEmpty && s != 'null' && s != 'undefined') return s;
      return null;
    }
    if (venue is Map) {
      if (venue['images'] is List && (venue['images'] as List).isNotEmpty) {
        final firstImg = (venue['images'] as List).first;
        if (firstImg is Map) {
          final fp =
              firstImg['filePath'] ?? firstImg['url'] ?? firstImg['image'];
          if (fp != null &&
              fp.toString().trim().isNotEmpty &&
              fp.toString() != 'null') {
            return fp.toString().trim();
          }
        } else if (firstImg is String &&
            firstImg.trim().isNotEmpty &&
            firstImg != 'null') {
          return firstImg.trim();
        }
      }
      final candidates = [
        venue['imageUrl'],
        venue['image'],
        venue['filePath'],
        venue['venueImageUrl'],
        venue['coverImage'],
        venue['photo'],
      ];
      for (final c in candidates) {
        if (c != null) {
          final s = c.toString().trim();
          if (s.isNotEmpty && s != 'null' && s != 'undefined') return s;
        }
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Unified Item Builders & Mapping (1 PLAN / 1 MEET = 1 SMART CARD)
  // ─────────────────────────────────────────────────────────────────────────────
  static bool _isPartyPlanItem(dynamic item) {
    if (item == null || item is! Map) return false;
    final map = item is Map<String, dynamic>
        ? item
        : Map<String, dynamic>.from(item);

    if (map['isPartyPlan'] == true) return true;
    if (map['partyPlanId'] != null ||
        map['partyEventId'] != null ||
        map['planId'] != null) {
      return true;
    }
    if (map['planDateTime'] != null || map['hostPaymentStatus'] != null) {
      return true;
    }

    final cat =
        (map['requestType'] ??
                map['type'] ??
                map['category'] ??
                map['entityType'] ??
                map['eventType'] ??
                map['bookingType'] ??
                '')
            .toString()
            .toLowerCase();
    if (cat.contains('party_plan') || cat == 'plan') return true;

    final goingMode =
        (map['goingMode'] ??
                map['booking']?['goingMode'] ??
                map['metadata']?['goingMode'] ??
                '')
            .toString()
            .toLowerCase();
    if (goingMode == 'plan') return true;

    final partySubject =
        (map['partySubject'] ??
                map['booking']?['partySubject'] ??
                map['metadata']?['partySubject'] ??
                '')
            .toString()
            .toLowerCase();
    if (partySubject.contains('party plan')) return true;

    final tablePackage =
        (map['tablePackage'] ??
                map['booking']?['tablePackage'] ??
                map['metadata']?['tablePackage'] ??
                '')
            .toString()
            .toLowerCase();
    if (tablePackage.contains('party plan')) return true;

    final rawId = (map['id'] ?? map['bookingId'] ?? map['entityId'] ?? '')
        .toString()
        .toLowerCase();
    if (rawId.startsWith('party_plan') || rawId.startsWith('pp_')) return true;

    if (map['booking'] is Map) {
      if (_isPartyPlanItem(map['booking'])) return true;
    }
    if (map['data'] is Map) {
      if (_isPartyPlanItem(map['data'])) return true;
    }
    if (map['metadata'] is Map) {
      if (_isPartyPlanItem(map['metadata'])) return true;
    }
    if (map['specialRequests'] != null &&
        map['specialRequests'].toString().contains('planId')) {
      return true;
    }

    return false;
  }

  static bool _isStrangerMeetItem(dynamic item) {
    if (item == null || item is! Map) return false;
    final map = item is Map<String, dynamic>
        ? item
        : Map<String, dynamic>.from(item);

    if (map['isStrangersMeet'] == true) return true;
    if (map['strangersMeetId'] != null ||
        map['meetId'] != null ||
        map['strangersMeetRequestId'] != null) {
      return true;
    }

    final cat =
        (map['requestType'] ??
                map['type'] ??
                map['category'] ??
                map['entityType'] ??
                map['eventType'] ??
                map['bookingType'] ??
                '')
            .toString()
            .toLowerCase();
    if (cat.contains('stranger') || cat.contains('meet')) return true;

    final goingMode =
        (map['goingMode'] ??
                map['booking']?['goingMode'] ??
                map['metadata']?['goingMode'] ??
                '')
            .toString()
            .toLowerCase();
    if (goingMode.contains('stranger')) return true;

    final partySubject =
        (map['partySubject'] ??
                map['booking']?['partySubject'] ??
                map['metadata']?['partySubject'] ??
                '')
            .toString()
            .toLowerCase();
    if (partySubject.contains('stranger')) return true;

    final tablePackage =
        (map['tablePackage'] ??
                map['booking']?['tablePackage'] ??
                map['metadata']?['tablePackage'] ??
                '')
            .toString()
            .toLowerCase();
    if (tablePackage.contains('stranger')) return true;

    final rawId = (map['id'] ?? map['bookingId'] ?? map['entityId'] ?? '')
        .toString()
        .toLowerCase();
    if (rawId.startsWith('strangers_meet') || rawId.startsWith('sm_')) {
      return true;
    }

    if (map['booking'] is Map) {
      if (_isStrangerMeetItem(map['booking'])) return true;
    }
    if (map['data'] is Map) {
      if (_isStrangerMeetItem(map['data'])) return true;
    }
    if (map['metadata'] is Map) {
      if (_isStrangerMeetItem(map['metadata'])) return true;
    }

    return false;
  }

  static bool _isUpcomingNightItem(dynamic item) {
    if (item == null || item is! Map) return false;
    final map = item is Map<String, dynamic>
        ? item
        : Map<String, dynamic>.from(item);

    if (map['isUpcomingNight'] == true || map['isNightPartner'] == true) {
      return true;
    }
    if (map['nightId'] != null ||
        map['nightPartnerId'] != null ||
        map['upcomingNightId'] != null) {
      return true;
    }

    final cat =
        (map['requestType'] ??
                map['type'] ??
                map['category'] ??
                map['entityType'] ??
                map['eventType'] ??
                map['bookingType'] ??
                '')
            .toString()
            .toLowerCase();
    if (cat.contains('upcoming_night') ||
        cat.contains('night_partner') ||
        cat.contains('night_match') ||
        cat.contains('partner_request')) {
      return true;
    }

    final rawId = (map['id'] ?? map['bookingId'] ?? map['entityId'] ?? '')
        .toString()
        .toLowerCase();
    if (rawId.startsWith('upcoming_night') ||
        rawId.startsWith('night_partner') ||
        rawId.startsWith('un_')) {
      return true;
    }

    if (map['booking'] is Map) {
      if (_isUpcomingNightItem(map['booking'])) return true;
    }
    if (map['data'] is Map) {
      if (_isUpcomingNightItem(map['data'])) return true;
    }
    if (map['metadata'] is Map) {
      if (_isUpcomingNightItem(map['metadata'])) return true;
    }

    return false;
  }

  String? _extractUpcomingNightId(Map<String, dynamic> item) {
    // 1. Authoritative Event Key (ONE EVENT = ONE CARD)
    final eventId = item['eventId'] ??
        item['data']?['eventId'] ??
        item['metadata']?['eventId'];
    if (eventId != null && eventId.toString().trim().isNotEmpty) {
      return eventId.toString().trim();
    }

    final venueId = item['venueId'] ??
        item['venue']?['id'] ??
        item['data']?['venueId'] ??
        item['metadata']?['venueId'];
    final eventDate = item['eventDate'] ??
        item['date'] ??
        item['bookingDate'] ??
        item['data']?['eventDate'] ??
        item['metadata']?['eventDate'];
    if (venueId != null && eventDate != null) {
      final vStr = venueId.toString().trim();
      final dStr = eventDate.toString().split('T')[0].split(' ')[0].trim();
      if (vStr.isNotEmpty && dStr.isNotEmpty) {
        return 'event_${vStr}_$dStr';
      }
    }

    if (item['data'] is Map && item['data']['nightId'] != null) {
      final id = item['data']['nightId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['nightId'] != null) {
      final id = item['metadata']['nightId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map && item['data']['matchId'] != null) {
      final id = item['data']['matchId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['matchId'] != null) {
      final id = item['metadata']['matchId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map && item['data']['requestId'] != null) {
      final id = item['data']['requestId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['requestId'] != null) {
      final id = item['metadata']['requestId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['nightId'] != null) {
      final id = item['nightId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['matchId'] != null) {
      final id = item['matchId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['requestId'] != null) {
      final id = item['requestId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['upcomingNightId'] != null) {
      final id = item['upcomingNightId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['booking'] is Map) {
      final b = item['booking'] as Map<String, dynamic>;
      if (b['nightId'] != null) return b['nightId'].toString().trim();
      if (b['bookingType'] == 'upcoming_night') {
        final id = b['id']?.toString() ?? '';
        if (id.isNotEmpty) return id;
      }
    }
    final rawId = item['id']?.toString() ?? item['entityId']?.toString() ?? '';
    if (rawId.startsWith('upcoming_night_timeline_') ||
        rawId.startsWith('upcoming_night_') ||
        rawId.startsWith('un_')) {
      return rawId
          .replaceAll('upcoming_night_timeline_', '')
          .replaceAll('upcoming_night_', '')
          .replaceAll('un_', '');
    }
    final cat =
        (item['requestType'] ??
                item['type'] ??
                item['category'] ??
                item['entityType'] ??
                item['eventType'] ??
                '')
            .toString()
            .toLowerCase();
    if (cat.contains('upcoming_night') ||
        cat.contains('night_partner') ||
        cat.contains('night_match') ||
        cat.contains('partner_request')) {
      if (rawId.isNotEmpty) return rawId;
    }
    return null;
  }

  String? _extractPartyPlanId(Map<String, dynamic> item) {
    if (item['data'] is Map && item['data']['partyPlanId'] != null) {
      final id = item['data']['partyPlanId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map && item['data']['planId'] != null) {
      final id = item['data']['planId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['partyPlanId'] != null) {
      final id = item['metadata']['partyPlanId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['planId'] != null) {
      final id = item['metadata']['planId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['partyPlanId'] != null) {
      final id = item['partyPlanId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['partyEventId'] != null) {
      final id = item['partyEventId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['booking'] is Map) {
      final b = item['booking'] as Map<String, dynamic>;
      if (b['partyPlanId'] != null) return b['partyPlanId'].toString().trim();
      if (b['partyEventId'] != null) return b['partyEventId'].toString().trim();
      if (b['goingMode']?.toString().toLowerCase() == 'plan' ||
          b['partySubject']?.toString().toLowerCase() == 'party plan') {
        final id =
            b['partyEventId']?.toString() ??
            b['partyPlanId']?.toString() ??
            b['id']?.toString() ??
            '';
        if (id.isNotEmpty) {
          return id
              .replaceAll('pp_', '')
              .replaceAll('party_plan_timeline_', '');
        }
      }
    }
    if (item['plan'] is Map && item['plan']['id'] != null) {
      final String cat =
          (item['requestType'] ??
                  item['type'] ??
                  item['category'] ??
                  item['entityType'] ??
                  '')
              .toString()
              .toLowerCase();
      if (cat.contains('party') ||
          cat == 'my_request' ||
          cat == 'incoming_request') {
        if (!cat.contains('stranger') && !cat.contains('meet')) {
          final id = item['plan']['id'].toString().trim();
          if (id.isNotEmpty) return id;
        }
      }
    }
    if (item['planId'] != null) {
      final String cat =
          (item['requestType'] ??
                  item['type'] ??
                  item['category'] ??
                  item['entityType'] ??
                  '')
              .toString()
              .toLowerCase();
      if (cat.contains('party') ||
          cat == 'my_request' ||
          cat == 'incoming_request') {
        if (!cat.contains('stranger') && !cat.contains('meet')) {
          final id = item['planId'].toString().trim();
          if (id.isNotEmpty) return id;
        }
      }
    }
    final String type =
        (item['type'] ??
                item['eventType'] ??
                item['category'] ??
                item['entityType'] ??
                '')
            .toString()
            .toLowerCase();
    final String goingMode =
        (item['goingMode'] ?? item['booking']?['goingMode'] ?? '')
            .toString()
            .toLowerCase();
    final String partySubject =
        (item['partySubject'] ?? item['booking']?['partySubject'] ?? '')
            .toString()
            .toLowerCase();

    if (goingMode == 'plan' || partySubject == 'party plan') {
      final id =
          item['partyEventId']?.toString() ??
          item['partyPlanId']?.toString() ??
          item['planId']?.toString() ??
          item['id']?.toString() ??
          '';
      if (id.isNotEmpty) {
        return id.replaceAll('pp_', '').replaceAll('party_plan_timeline_', '');
      }
    }

    if (type == 'party_plan' ||
        type == 'party_plan_timeline' ||
        type.contains('party_plan')) {
      final id = item['id']?.toString() ?? item['entityId']?.toString() ?? '';
      if (id.isNotEmpty && !id.startsWith('sm_') && !id.startsWith('gp_')) {
        return id
            .replaceAll('pp_', '')
            .replaceAll('party_plan_timeline_', '')
            .replaceAll('pp_host_deposit_', '');
      }
    }
    return null;
  }

  String? _extractStrangersMeetId(Map<String, dynamic> item) {
    if (item['data'] is Map && item['data']['strangersMeetId'] != null) {
      final id = item['data']['strangersMeetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map && item['data']['meetId'] != null) {
      final id = item['data']['meetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map &&
        item['metadata']['strangersMeetId'] != null) {
      final id = item['metadata']['strangersMeetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['meetId'] != null) {
      final id = item['metadata']['meetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['strangersMeetId'] != null) {
      final id = item['strangersMeetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['meetId'] != null) {
      final id = item['meetId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['planDetails'] is Map && item['planDetails']['id'] != null) {
      final id = item['planDetails']['id'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map &&
        item['data']['planDetails'] is Map &&
        item['data']['planDetails']['id'] != null) {
      final id = item['data']['planDetails']['id'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['strangersMeet'] is Map && item['strangersMeet']['id'] != null) {
      final id = item['strangersMeet']['id'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map &&
        item['data']['strangersMeet'] is Map &&
        item['data']['strangersMeet']['id'] != null) {
      final id = item['data']['strangersMeet']['id'].toString().trim();
      if (id.isNotEmpty) return id;
    }

    final String entityType = (item['entityType'] ?? '')
        .toString()
        .toLowerCase();
    final String eventType = (item['eventType'] ?? '').toString().toLowerCase();
    final String reqType = (item['requestType'] ?? item['type'] ?? '')
        .toString()
        .toLowerCase();
    final String category = (item['category'] ?? '').toString().toLowerCase();
    final String title = (item['title'] ?? '').toString().toLowerCase();
    final String body = (item['body'] ?? '').toString().toLowerCase();

    final bool isStranger =
        entityType.contains('stranger') ||
        eventType.contains('stranger') ||
        reqType.contains('stranger') ||
        category.contains('stranger') ||
        (title.contains('stranger meet') ||
            body.contains('stranger meet') ||
            (category == 'bookings' && entityType.contains('stranger')));

    if (isStranger) {
      if (item['plan'] is Map && item['plan']['id'] != null) {
        return item['plan']['id'].toString().trim();
      }
      if (item['planId'] != null) {
        return item['planId'].toString().trim();
      }
      if (item['data'] is Map && item['data']['planId'] != null) {
        return item['data']['planId'].toString().trim();
      }
      if (item['metadata'] is Map && item['metadata']['planId'] != null) {
        return item['metadata']['planId'].toString().trim();
      }
      if (item['entityId'] != null &&
          item['entityId'].toString().trim().isNotEmpty) {
        return item['entityId']
            .toString()
            .trim()
            .replaceAll('sm_', '')
            .replaceAll('strangers_meet_timeline_', '');
      }
      if (item['data'] is Map && item['data']['requestId'] != null) {
        final id = item['data']['requestId'].toString().trim();
        if (id.isNotEmpty) return id;
      }
      if (item['metadata'] is Map && item['metadata']['requestId'] != null) {
        final id = item['metadata']['requestId'].toString().trim();
        if (id.isNotEmpty) return id;
      }
      if (item['strangersMeetRequestId'] != null) {
        return item['strangersMeetRequestId'].toString().trim();
      }
      if (item['request'] is Map && item['request']['id'] != null) {
        return item['request']['id'].toString().trim();
      }
      if (item['joiner'] is Map &&
          item['joiner']['strangersMeetRequestId'] != null) {
        return item['joiner']['strangersMeetRequestId'].toString().trim();
      }
      final id = item['id']?.toString() ?? '';
      if (id.isNotEmpty && !id.startsWith('pp_') && !id.startsWith('gp_')) {
        return id
            .replaceAll('sm_', '')
            .replaceAll('strangers_meet_timeline_', '')
            .replaceAll('sm_host_deposit_', '')
            .replaceAll('sm_host_approved_', '');
      }
    }
    return null;
  }

  String? _extractGroupPartyId(Map<String, dynamic> item) {
    final String cat =
        (item['requestType'] ??
                item['type'] ??
                item['category'] ??
                item['entityType'] ??
                item['eventType'] ??
                '')
            .toString()
            .toLowerCase();
    final String paymentCategory = (item['paymentCategory'] ?? '')
        .toString()
        .toLowerCase();
    final String title = (item['title'] ?? '').toString().toLowerCase();
    final String body = (item['body'] ?? '').toString().toLowerCase();

    // Skip party plans
    if (cat.contains('party_plan') ||
        cat == 'party_plan' ||
        cat == 'plan' ||
        item['partyPlanId'] != null ||
        item['partyEventId'] != null ||
        item['planId'] != null ||
        item['booking']?['goingMode']?.toString() == 'plan' ||
        item['goingMode']?.toString() == 'plan' ||
        item['partySubject']?.toString().toLowerCase() == 'party plan' ||
        (item['specialRequests'] != null &&
            (item['specialRequests'].toString().contains('partyPlanId') ||
                item['specialRequests'].toString().contains('planId')))) {
      return null;
    }

    final dynamic rawGuests =
        item['numberOfGuests'] ??
        item['guestCount'] ??
        item['numberOfFriends'] ??
        item['booking']?['numberOfGuests'] ??
        item['booking']?['guestCount'] ??
        1;
    final int guestCount = rawGuests is num
        ? rawGuests.toInt()
        : (int.tryParse(rawGuests.toString()) ?? 1);
    final bool isLargeOrGroup =
        guestCount >= 2 ||
        cat.contains('group_party') ||
        cat.contains('large_party') ||
        cat.contains('large_party_approved') ||
        cat.contains('large_party_rejected') ||
        cat.contains('large_party_payment_link') ||
        cat == 'group_party_small' ||
        cat == 'group_party_large' ||
        paymentCategory.contains('large_party') ||
        paymentCategory.contains('group_party') ||
        item['isLargePartyRequest'] == true ||
        item['isLargeParty'] == true ||
        item['isGroupParty'] == true ||
        item['isSmallGroupParty'] == true ||
        item['isLargeBooking'] == true ||
        item['goingMode'] == 'party_request' ||
        item['goingMode'] == 'with_friends' ||
        item['payActionPayload']?['isLargeParty'] == true ||
        item['payActionPayload']?['goingMode'] == 'party_request' ||
        item['booking']?['isLargePartyRequest'] == true ||
        item['booking']?['goingMode'] == 'party_request' ||
        item['booking']?['goingMode'] == 'with_friends' ||
        title.contains('large party') ||
        title.contains('group party') ||
        body.contains('large party') ||
        body.contains('group party');

    if (item['data'] is Map && item['data']['partyId'] != null) {
      final id = item['data']['partyId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map && item['data']['groupPartyId'] != null) {
      final id = item['data']['groupPartyId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['data'] is Map && item['data']['bookingId'] != null) {
      final id = item['data']['bookingId'].toString().trim();
      if (id.isNotEmpty &&
          (isLargeOrGroup ||
              item['data']['type']?.toString().contains('group_party') ==
                  true ||
              item['data']['type']?.toString().contains('large_party') ==
                  true)) {
        return id;
      }
    }
    if (item['metadata'] is Map && item['metadata']['groupPartyId'] != null) {
      final id = item['metadata']['groupPartyId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['partyId'] != null) {
      final id = item['metadata']['partyId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['metadata'] is Map && item['metadata']['bookingId'] != null) {
      final id = item['metadata']['bookingId'].toString().trim();
      if (id.isNotEmpty && isLargeOrGroup) return id;
    }
    if (item['groupPartyId'] != null) {
      final id = item['groupPartyId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['partyId'] != null) {
      final id = item['partyId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['bookingId'] != null && isLargeOrGroup) {
      final id = item['bookingId'].toString().trim();
      if (id.isNotEmpty) return id;
    }
    if (item['payActionPayload'] is Map &&
        item['payActionPayload']['bookingId'] != null &&
        isLargeOrGroup) {
      final id = item['payActionPayload']['bookingId'].toString().trim();
      if (id.isNotEmpty) return id;
    }

    if (isLargeOrGroup) {
      final id = item['id']?.toString() ?? item['entityId']?.toString() ?? '';
      if (id.isNotEmpty) {
        final cleanId = id
            .replaceAll('group_party_timeline_', '')
            .replaceAll('group_party_', '')
            .replaceAll('large_party_timeline_', '')
            .replaceAll('large_party_', '')
            .replaceAll('pending_bk_', '')
            .replaceAll('pending_', '')
            .replaceAll('solo_booking_', '')
            .replaceAll('bk_', '')
            .replaceAll('gp_', '')
            .replaceAll('_confirmed', '')
            .replaceAll('_approved', '')
            .replaceAll('_rejected', '')
            .replaceAll('_cancelled', '')
            .replaceAll('_payment_success', '');
        if (cleanId.isNotEmpty) return cleanId;
      }
    }
    return null;
  }

  // Helper to extract Solo and standard venue booking ID
  String? _extractSoloBookingId(dynamic item) {
    if (item == null || item is! Map) return null;
    if (_isPartyPlanItem(item) ||
        _isStrangerMeetItem(item) ||
        item['partyPlanId'] != null ||
        item['partyEventId'] != null ||
        item['planId'] != null ||
        item['goingMode']?.toString() == 'plan' ||
        item['booking']?['goingMode']?.toString() == 'plan' ||
        item['partySubject']?.toString().toLowerCase() == 'party plan' ||
        (item['specialRequests'] != null &&
            (item['specialRequests'].toString().contains('partyPlanId') ||
                item['specialRequests'].toString().contains('planId')))) {
      return null;
    }

    final cat =
        (item['requestType'] ??
                item['type'] ??
                item['category'] ??
                item['entityType'] ??
                item['eventType'] ??
                item['bookingType'] ??
                '')
            .toString()
            .toLowerCase();
    final goingMode =
        (item['goingMode'] ??
                item['booking']?['goingMode'] ??
                item['metadata']?['goingMode'] ??
                '')
            .toString()
            .toLowerCase();
    final dynamic rawGuests =
        item['numberOfGuests'] ??
        item['guestCount'] ??
        item['numberOfFriends'] ??
        item['booking']?['numberOfGuests'] ??
        item['booking']?['guestCount'] ??
        0;
    final int guestCount = rawGuests is num
        ? rawGuests.toInt()
        : (int.tryParse(rawGuests.toString()) ?? 0);
    final isLargeOrGroup =
        guestCount >= 2 ||
        item['isLargePartyRequest'] == true ||
        item['isLargeParty'] == true ||
        item['isGroupParty'] == true ||
        item['isSmallGroupParty'] == true ||
        item['isLargeBooking'] == true ||
        cat.contains('group_party') ||
        cat.contains('large_party') ||
        goingMode == 'party_request' ||
        goingMode == 'with_friends';

    if (isLargeOrGroup) {
      return null;
    }

    if (item['data'] is Map &&
        (item['data']['type'] == 'venue_booking_timeline' ||
            item['data']['type'] == 'venue_booking')) {
      final id = (item['data']['bookingId'] ?? item['data']['id'])
          ?.toString()
          .trim();
      if (id != null && id.isNotEmpty) return id;
    }

    if (item['eventType'] == 'booking_confirmed' ||
        item['eventType'] == 'booking_cancelled' ||
        item['eventType'] == 'booking_pending_payment' ||
        item['eventType'] == 'venue_booking_received') {
      final id =
          (item['entityId'] ??
                  item['bookingId'] ??
                  item['data']?['bookingId'] ??
                  item['metadata']?['bookingId'])
              ?.toString()
              .trim();
      if (id != null && id.isNotEmpty) return id;
    }

    final id =
        item['bookingId'] ??
        item['booking']?['id'] ??
        item['booking']?['bookingId'] ??
        item['data']?['bookingId'] ??
        item['metadata']?['bookingId'];
    if (id != null && id.toString().trim().isNotEmpty) {
      return id.toString().trim();
    }

    final rawId = (item['id'] ?? item['entityId'])?.toString() ?? '';
    if (rawId.startsWith('venue_booking_timeline_') ||
        rawId.startsWith('solo_booking_') ||
        rawId.startsWith('venue_booking_')) {
      final cleanId = ApiService.cleanBookingId(rawId);
      if (cleanId.isNotEmpty) return cleanId;
    } else if (rawId.isNotEmpty &&
        (item['venueId'] != null ||
            item['venue'] != null ||
            item['bookingDate'] != null)) {
      if (rawId.startsWith('party_plan_') ||
          rawId.startsWith('pp_') ||
          rawId.startsWith('strangers_meet_') ||
          rawId.startsWith('sm_') ||
          rawId.startsWith('group_party_') ||
          rawId.startsWith('gp_')) {
        return null;
      }
      return rawId.trim();
    }

    return null;
  }

  List<UnifiedNotificationItem> _buildUnifiedTimeline() {
    final List<UnifiedNotificationItem> items = [];
    final currentUserId = ApiService.currentUserId ?? '';

    // 1. Partition entries into Party Plan, Stranger Meet, Upcoming Night, Group Party, Solo Booking, and General Notifications
    final Map<String, List<Map<String, dynamic>>> partyPlanGroups = {};
    final Map<String, List<Map<String, dynamic>>> strangersMeetGroups = {};
    final Map<String, List<Map<String, dynamic>>> upcomingNightGroups = {};
    final Map<String, List<Map<String, dynamic>>> groupPartyGroups = {};
    final Map<String, List<Map<String, dynamic>>> soloBookingGroups = {};
    final List<Map<String, dynamic>> nonPartyNotifications = [];
    final List<Map<String, dynamic>> nonPartyFeedItems = [];

    for (final n in _notifications) {
      final ppId = _extractPartyPlanId(n);
      final smId = _extractStrangersMeetId(n);
      final unId = _extractUpcomingNightId(n);
      final gpId = _extractGroupPartyId(n);
      final soloId = _extractSoloBookingId(n);

      if (ppId != null && ppId.isNotEmpty) {
        partyPlanGroups.putIfAbsent(ppId, () => []).add(n);
      } else if (smId != null && smId.isNotEmpty) {
        strangersMeetGroups.putIfAbsent(smId, () => []).add(n);
      } else if (unId != null && unId.isNotEmpty) {
        upcomingNightGroups.putIfAbsent(unId, () => []).add(n);
      } else if (gpId != null && gpId.isNotEmpty) {
        groupPartyGroups.putIfAbsent(gpId, () => []).add(n);
      } else if (soloId != null && soloId.isNotEmpty) {
        soloBookingGroups.putIfAbsent(soloId, () => []).add(n);
      } else {
        nonPartyNotifications.add(n);
      }
    }

    for (final fi in _feedItems) {
      final ppId = _extractPartyPlanId(fi);
      final smId = _extractStrangersMeetId(fi);
      final unId = _extractUpcomingNightId(fi);
      final gpId = _extractGroupPartyId(fi);
      final soloId = _extractSoloBookingId(fi);

      if (ppId != null && ppId.isNotEmpty) {
        partyPlanGroups.putIfAbsent(ppId, () => []).add(fi);
      } else if (smId != null && smId.isNotEmpty) {
        strangersMeetGroups.putIfAbsent(smId, () => []).add(fi);
      } else if (unId != null && unId.isNotEmpty) {
        upcomingNightGroups.putIfAbsent(unId, () => []).add(fi);
      } else if (gpId != null && gpId.isNotEmpty) {
        groupPartyGroups.putIfAbsent(gpId, () => []).add(fi);
      } else if (soloId != null && soloId.isNotEmpty) {
        soloBookingGroups.putIfAbsent(soloId, () => []).add(fi);
      } else {
        nonPartyFeedItems.add(fi);
      }
    }

    for (final booking in _userBookings) {
      if (_isPartyPlanItem(booking) ||
          _isStrangerMeetItem(booking) ||
          _isUpcomingNightItem(booking) ||
          (booking['goingMode'] ?? '').toString().toLowerCase() == 'plan' ||
          (booking['partySubject'] ?? '').toString().toLowerCase() == 'party plan' ||
          booking['partyPlanId'] != null ||
          booking['partyEventId'] != null ||
          booking['planId'] != null ||
          (booking['specialRequests'] != null &&
              (booking['specialRequests'].toString().contains('partyPlanId') ||
                  booking['specialRequests'].toString().contains('planId')))) {
        continue; // Never render party plans, stranger meets, or upcoming nights as solo/table bookings!
      }
      final dynamic rawGuests =
          booking['numberOfGuests'] ??
          booking['guestCount'] ??
          booking['numberOfFriends'] ??
          1;
      final int guestCount = rawGuests is num
          ? rawGuests.toInt()
          : (int.tryParse(rawGuests.toString()) ?? 1);
      final isLargeOrGroup =
          guestCount >= 2 ||
          booking['isLargePartyRequest'] == true ||
          booking['isLargeParty'] == true ||
          booking['isGroupParty'] == true ||
          booking['isSmallGroupParty'] == true ||
          booking['isLargeBooking'] == true ||
          (booking['goingMode'] ?? '').toString().toLowerCase() ==
              'party_request' ||
          (booking['goingMode'] ?? '').toString().toLowerCase() ==
              'with_friends';
      if (isLargeOrGroup) {
        final gpId = _extractGroupPartyId(booking) ?? booking['id']?.toString();
        if (gpId != null && gpId.isNotEmpty) {
          groupPartyGroups.putIfAbsent(gpId, () => []).add(booking);
        }
      } else {
        final soloId = _extractSoloBookingId(booking);
        if (soloId != null && soloId.isNotEmpty) {
          soloBookingGroups.putIfAbsent(soloId, () => []).add(booking);
        }
      }
    }

    for (final booking in _largePartyBookings) {
      if (_isPartyPlanItem(booking) ||
          _isStrangerMeetItem(booking) ||
          _isUpcomingNightItem(booking)) {
        continue;
      }
      final gpId =
          _extractGroupPartyId(booking) ??
          booking['id']?.toString() ??
          booking['bookingId']?.toString();
      if (gpId != null && gpId.isNotEmpty) {
        groupPartyGroups.putIfAbsent(gpId, () => []).add(booking);
      }
    }

    // 2. Build Exactly ONE Authoritative Smart Card per Party Plan
    for (final entry in partyPlanGroups.entries) {
      final planId = entry.key;
      final planEntries = entry.value;
      final smartCard = _buildAuthoritativePartyPlanCard(
        planId,
        planEntries,
        currentUserId,
      );
      if (smartCard != null) {
        items.add(smartCard);
      }
    }

    // 3. Build Exactly ONE Authoritative Smart Card per Stranger Meet
    for (final entry in strangersMeetGroups.entries) {
      final meetId = entry.key;
      final meetEntries = entry.value;
      final smartCard = _buildAuthoritativeStrangersMeetCard(
        meetId,
        meetEntries,
        currentUserId,
      );
      if (smartCard != null) {
        items.add(smartCard);
      }
    }

    // 4. Build Exactly ONE Authoritative Smart Card per Upcoming Night
    for (final entry in upcomingNightGroups.entries) {
      final nightId = entry.key;
      final nightEntries = entry.value;
      final smartCard = _buildAuthoritativeUpcomingNightCard(
        nightId,
        nightEntries,
        currentUserId,
      );
      if (smartCard != null) {
        items.add(smartCard);
      }
    }

    final Set<String> processedBookingIds = {};

    // 4. Build Exactly ONE Authoritative Smart Card per Group Party
    for (final entry in groupPartyGroups.entries) {
      final partyId = entry.key;
      final partyEntries = entry.value;
      final smartCard = _buildAuthoritativeGroupPartyCard(
        partyId,
        partyEntries,
        currentUserId,
      );
      if (smartCard != null) {
        items.add(smartCard);
        processedBookingIds.add(partyId);
        final cleanId = ApiService.cleanBookingId(partyId);
        if (cleanId.isNotEmpty) processedBookingIds.add(cleanId);
        for (final e in partyEntries) {
          final bId =
              e['bookingId']?.toString() ??
              e['id']?.toString() ??
              e['data']?['bookingId']?.toString();
          if (bId != null && bId.isNotEmpty) {
            processedBookingIds.add(bId);
            processedBookingIds.add(ApiService.cleanBookingId(bId));
          }
        }
      }
    }

    // 5. Build Exactly ONE Authoritative Smart Card per Solo & Venue Table Booking
    for (final entry in soloBookingGroups.entries) {
      final bookingId = entry.key;
      final cleanId = ApiService.cleanBookingId(bookingId);
      if (processedBookingIds.contains(bookingId) ||
          processedBookingIds.contains(cleanId)) {
        continue; // Prevent duplicate solo card when party card was already built!
      }
      final bookingEntries = entry.value;
      final smartCard = _buildAuthoritativeSoloBookingCard(
        bookingId,
        bookingEntries,
        currentUserId,
      );
      if (smartCard != null) {
        items.add(smartCard);
        processedBookingIds.add(bookingId);
        if (cleanId.isNotEmpty) processedBookingIds.add(cleanId);
        for (final e in bookingEntries) {
          final bId =
              e['bookingId']?.toString() ??
              e['id']?.toString() ??
              e['data']?['bookingId']?.toString();
          if (bId != null && bId.isNotEmpty) {
            processedBookingIds.add(bId);
            processedBookingIds.add(ApiService.cleanBookingId(bId));
          }
        }
      }
    }

    // 6. Process General Push Notifications (Table Plans, System, Wallet, Promo)
    for (final n in nonPartyNotifications) {
      final String goingMode =
          (n['goingMode'] ??
                  n['booking']?['goingMode'] ??
                  n['metadata']?['goingMode'] ??
                  '')
              .toString()
              .toLowerCase();
      final String partySubject =
          (n['partySubject'] ??
                  n['booking']?['partySubject'] ??
                  n['metadata']?['partySubject'] ??
                  '')
              .toString()
              .toLowerCase();
      final String cat =
          (n['requestType'] ??
                  n['type'] ??
                  n['category'] ??
                  n['entityType'] ??
                  n['eventType'] ??
                  '')
              .toString()
              .toLowerCase();
      final String titleLower = (n['title'] ?? '').toString().toLowerCase();
      final String bodyLower = (n['body'] ?? '').toString().toLowerCase();

      // Skip party plan, stranger meet & upcoming night confirmation/reminders — consolidated into their dedicated cards
      if (_isPartyPlanItem(n) ||
          _isStrangerMeetItem(n) ||
          _isUpcomingNightItem(n) ||
          goingMode == 'plan' ||
          partySubject.contains('party plan') ||
          cat.contains('party_plan') ||
          cat.contains('upcoming_night') ||
          cat.contains('night_partner') ||
          (cat.contains('match_confirmed') &&
              (n['metadata']?['planId'] != null ||
                  n['metadata']?['partyPlanId'] != null)) ||
          goingMode.contains('stranger') ||
          partySubject.contains('stranger') ||
          cat.contains('stranger') ||
          titleLower.contains('stranger meet') ||
          bodyLower.contains('stranger meet')) {
        continue;
      }

      final notifBookingId = ApiService.cleanBookingId(
        (n['data']?['bookingId'] ??
                n['bookingId'] ??
                n['entityId'] ??
                n['id'] ??
                '')
            .toString(),
      );
      if (notifBookingId.isNotEmpty &&
          processedBookingIds.contains(notifBookingId)) {
        continue; // Authoritative card already rendered for this booking!
      }
      if (notifBookingId.isNotEmpty &&
          (cat.contains('booking') ||
              n['id']?.toString().startsWith('venue_booking_') == true)) {
        processedBookingIds.add(notifBookingId);
      }

      final id = n['id']?.toString() ?? '';
      final category = (n['category'] ?? n['entityType'] ?? 'system')
          .toString()
          .toLowerCase();
      final title = n['title']?.toString() ?? 'Notification';
      final body = n['body']?.toString() ?? '';
      final isRead =
          n['read'] == true ||
          n['isRead'] == true ||
          (n['is_read'] == true) ||
          (n['isSeen'] == true) ||
          (n['seen'] == true) ||
          _localReadNotificationIds.contains(id) ||
          ApiService.localReadRequestIds.contains(id);
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
        actionTap = () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
        );
      } else if (category.contains('wallet') || category.contains('credit')) {
        accentColor = const Color(0xFF3B82F6);
        icon = Icons.account_balance_wallet_rounded;
        badge = 'WALLET';
        actionText = 'Open Wallet';
        actionTap = () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
        );
      } else if (category.contains('chat') || category.contains('message')) {
        accentColor = const Color(0xFFEC4899);
        icon = Icons.chat_bubble_rounded;
        badge = 'CHAT';
      } else if (category.contains('cancel')) {
        accentColor = const Color(0xFFEF4444);
        icon = Icons.cancel_rounded;
        badge = 'CANCELLED';
      } else if (category.contains('super_like') ||
          category.contains('superlike') ||
          (n['type']?.toString().contains('super_like') == true) ||
          (n['data']?['action'] == 'superlike')) {
        accentColor = const Color(0xFF8B5CF6);
        icon = Icons.star_rounded;
        badge = 'SUPER LIKE';
        final sId =
            (n['sender'] is Map ? n['sender']['id'] : null) ??
            n['data']?['senderId'] ??
            n['actorUserId'];
        if (sId != null && sId.toString().isNotEmpty) {
          final sName =
              (n['sender'] is Map ? n['sender']['firstName'] : null) ??
              n['data']?['senderName'] ??
              'Someone';
          final sPhoto =
              (n['sender'] is Map ? n['sender']['profileImageUrl'] : null) ??
              n['data']?['senderImage'];
          actionText = 'View Profile';
          actionTap = () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                user: User.fromJson({
                  'id': sId.toString(),
                  'firstName': sName.toString(),
                  'photos': sPhoto != null
                      ? [
                          {'url': sPhoto.toString()},
                        ]
                      : [],
                }),
              ),
            ),
          );
        }
      } else if (category.contains('like')) {
        accentColor = const Color(0xFFEC4899);
        icon = Icons.favorite_rounded;
        badge = 'LIKE';
      } else if (category.contains('promo') || category.contains('offer')) {
        accentColor = const Color(0xFFF59E0B);
        icon = Icons.card_giftcard_rounded;
        badge = 'PROMO';
      }

      bool isExpired = false;
      final planData = n['plan'] is Map ? n['plan'] : n;
      final rawDateTime =
          planData['planDateTime'] ??
          planData['eventDateTime'] ??
          planData['planDate'] ??
          planData['partyDate'] ??
          planData['bookingDate'] ??
          n['entityDetails']?['planDateTime'] ??
          n['entityDetails']?['eventDateTime'];
      final rawStartTime =
          planData['startTime'] ??
          planData['time'] ??
          planData['bookingTime'] ??
          n['entityDetails']?['startTime'];
      if (rawDateTime != null) {
        final planTime = _parseEventDateTime(rawDateTime, rawStartTime);
        if (planTime != null &&
            DateTime.now().isAfter(planTime.add(const Duration(hours: 4)))) {
          isExpired = true;
        }
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
          : (n['sender'] is Map
                ? Map<String, dynamic>.from(n['sender'])
                : null);

      items.add(
        UnifiedNotificationItem(
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
          avatarUrl:
              n['imageUrl']?.toString() ??
              actorMap?['profilePhotoUrl']?.toString() ??
              actorMap?['profileImageUrl']?.toString(),
          senderUser: actorMap,
          actionButtonText: actionText,
          onActionTap: actionTap,
          actions: isExpired ? null : actionsList,
          rawData: n,
        ),
      );
    }

    // 6. Process Non-Party Feed Items (Pending Bookings, Table Plan Join Requests, System Action Items)
    for (final fi in nonPartyFeedItems) {
      final String goingMode =
          (fi['goingMode'] ?? fi['booking']?['goingMode'] ?? '')
              .toString()
              .toLowerCase();
      final String partySubject =
          (fi['partySubject'] ?? fi['booking']?['partySubject'] ?? '')
              .toString()
              .toLowerCase();
      final String cat =
          (fi['requestType'] ??
                  fi['type'] ??
                  fi['category'] ??
                  fi['entityType'] ??
                  '')
              .toString()
              .toLowerCase();
      final String titleLower = (fi['title'] ?? '').toString().toLowerCase();
      final String bodyLower = (fi['body'] ?? '').toString().toLowerCase();

      // Skip party plans, stranger meets & upcoming nights — they are already rendered in their authoritative smart card
      if (_isPartyPlanItem(fi) ||
          _isStrangerMeetItem(fi) ||
          _isUpcomingNightItem(fi) ||
          goingMode == 'plan' ||
          partySubject.contains('party plan') ||
          cat.contains('party_plan') ||
          cat.contains('upcoming_night') ||
          cat.contains('night_partner') ||
          goingMode.contains('stranger') ||
          partySubject.contains('stranger') ||
          cat.contains('stranger') ||
          titleLower.contains('stranger meet') ||
          bodyLower.contains('stranger meet')) {
        continue;
      }

      final fiBookingId = ApiService.cleanBookingId(
        (fi['bookingId'] ??
                fi['booking']?['id'] ??
                fi['booking']?['bookingId'] ??
                fi['payActionPayload']?['bookingId'] ??
                fi['groupPartyId'] ??
                fi['id'] ??
                '')
            .toString(),
      );
      if (fiBookingId.isNotEmpty && processedBookingIds.contains(fiBookingId)) {
        continue; // Authoritative card already rendered! Keep ONLY ONE card!
      }

      final id = fi['id']?.toString() ?? '';
      final isPendingPayment =
          fi['hasPendingPayment'] == true ||
          fi['type'] == 'pending_payment' ||
          fi['requestType'] == 'booking_payment' ||
          fi['paymentStatus'] == 'pending' ||
          fi['status'] == 'payment_pending';

      if (fiBookingId.isNotEmpty) {
        processedBookingIds.add(fiBookingId);
      }

      final dynamic rawAmt =
          fi['amountDue'] ?? fi['totalAmount'] ?? fi['depositAmount'] ?? 0;
      final int displayAmt = (rawAmt is num)
          ? rawAmt.round()
          : (int.tryParse(rawAmt.toString().split('.').first) ?? 0);
      final title =
          fi['title']?.toString() ??
          (isPendingPayment
              ? 'Payment Required 💳'
              : (fi['partySubject'] ?? 'Table Booking'));
      final body =
          fi['body']?.toString() ??
          (isPendingPayment
              ? 'Action Required: Complete payment of ₹$displayAmt to confirm your reservation at ${fi['venueName'] ?? fi['venue']?['name'] ?? 'Venue'}.'
              : 'Booking at ${fi['venueName'] ?? fi['venue']?['name'] ?? 'Venue'}');
      final isRead = false; // Action required is active!
      final createdAt = _parseDateTime(fi['createdAt']);
      final timeAgo = _formatTimeAgo(fi['createdAt']);

      Color accentColor = isPendingPayment
          ? const Color(0xFFF59E0B)
          : const Color(0xFF7C3AED);
      IconData icon = isPendingPayment
          ? Icons.payment_rounded
          : Icons.confirmation_number_rounded;
      String? badge = isPendingPayment ? 'ACTION REQUIRED' : 'BOOKING';
      String? actionText = isPendingPayment ? 'Pay Now' : null;
      VoidCallback? actionTap;

      if (isPendingPayment) {
        final bookingData = fi['booking'] is Map
            ? Map<String, dynamic>.from(fi['booking'])
            : fi;
        final payPayload = fi['payActionPayload'] is Map
            ? Map<String, dynamic>.from(fi['payActionPayload'])
            : bookingData;
        actionTap = () => _initiatePendingBookingPayment(payPayload);
      }

      List<NotificationAction>? actionsList;
      if (actionText != null && actionTap != null) {
        actionsList = [
          NotificationAction(
            label: actionText,
            onTap: actionTap,
            isPrimary: true,
            icon: Icons.credit_card_rounded,
          ),
        ];
      }

      items.add(
        UnifiedNotificationItem(
          id: id.isNotEmpty
              ? id
              : 'item_${DateTime.now().millisecondsSinceEpoch}',
          category: 'booking',
          title: title,
          body: body,
          createdAt: createdAt,
          timeAgo: timeAgo,
          isRead: isRead,
          isExpired: false,
          priority: isPendingPayment ? 'CRITICAL' : 'NORMAL',
          badgeText: badge,
          accentColor: accentColor,
          categoryIcon: icon,
          avatarUrl:
              _extractVenuePhoto(fi['venue']) ??
              _extractVenuePhoto(fi) ??
              fi['venueImageUrl']?.toString(),
          actionButtonText: actionText,
          onActionTap: actionTap,
          actions: actionsList,
          rawData: fi,
          statusSummary: isPendingPayment
              ? 'Payment Pending'
              : (fi['status']?.toString().toUpperCase()),
        ),
      );
    }

    // Sort all timeline items:
    // 1. Action Required / Critical / Invites first
    // 2. Unread items second
    // 3. Descending by createdAt (lastActivityAt)
    items.sort((a, b) {
      final aAction =
          (a.badgeText == 'ACTION REQUIRED' ||
              a.badgeText == 'NEW REQUEST' ||
              a.priority == 'CRITICAL' ||
              a.badgeText == 'INVITE')
          ? 1
          : 0;
      final bAction =
          (b.badgeText == 'ACTION REQUIRED' ||
              b.badgeText == 'NEW REQUEST' ||
              b.priority == 'CRITICAL' ||
              b.badgeText == 'INVITE')
          ? 1
          : 0;
      if (aAction != bAction) return bAction - aAction;

      final aUnread = (!a.isRead && !a.isExpired) ? 1 : 0;
      final bUnread = (!b.isRead && !b.isExpired) ? 1 : 0;
      if (aUnread != bUnread) return bUnread - aUnread;

      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Authoritative Group Party Smart Card (1 Group Party = 1 Card)
  // ─────────────────────────────────────────────────────────────────────────────
  UnifiedNotificationItem? _buildAuthoritativeGroupPartyCard(
    String partyId,
    List<Map<String, dynamic>> entries,
    String currentUserId,
  ) {
    if (entries.isEmpty) return null;

    // Extract best representative map
    Map<String, dynamic> partyMap = {};
    for (final e in entries) {
      if (e['data'] is Map &&
          (e['data']['type'] == 'group_party_timeline' ||
              e['data']['partyId'] != null)) {
        partyMap = Map<String, dynamic>.from(e['data']);
        break;
      }
      if (e['type'] == 'group_party_timeline' ||
          e['category'] == 'group_party' ||
          e['category'] == 'large_party') {
        partyMap = Map<String, dynamic>.from(e);
        break;
      }
    }
    if (partyMap.isEmpty) {
      partyMap = Map<String, dynamic>.from(entries.first);
      if (partyMap['data'] is Map) {
        partyMap.addAll(Map<String, dynamic>.from(partyMap['data']));
      }
    }

    // Extract total amount to determine if this party is paid or free
    double totalAmount = 0.0;
    for (final e in entries) {
      final rawAmt =
          e['totalAmount'] ??
          e['amount'] ??
          e['approvedAmount'] ??
          e['adminPaymentAmount'] ??
          e['charges'] ??
          e['data']?['totalAmount'] ??
          e['data']?['amount'];
      if (rawAmt is num && rawAmt > 0) {
        totalAmount = rawAmt.toDouble();
        break;
      } else if (rawAmt != null) {
        final parsed = double.tryParse(rawAmt.toString());
        if (parsed != null && parsed > 0) {
          totalAmount = parsed;
          break;
        }
      }
    }
    if (totalAmount > 0) {
      partyMap['totalAmount'] = totalAmount;
    }

    // Ensure startTime is extracted from entries into partyMap
    for (final e in entries) {
      final st =
          e['startTime'] ??
          e['time'] ??
          e['bookingTime'] ??
          e['data']?['startTime'] ??
          e['data']?['time'];
      if (st != null && st.toString().trim().isNotEmpty) {
        partyMap['startTime'] = LunaraDateFormatter.normalizeTimeTo12Hour(
          st.toString(),
        );
        break;
      }
    }

    // Determine status from entries
    bool isConfirmed = false;
    bool isApproved = false;
    bool isPending = false;
    bool isCancelled = false;
    bool isCompleted = false;
    bool isExpiredFromServer = false;

    for (final e in entries) {
      final status =
          (e['status'] ??
                  e['bookingStatus'] ??
                  e['data']?['status'] ??
                  e['adminApprovalStatus'] ??
                  '')
              .toString()
              .toLowerCase();
      final paymentStatus =
          (e['paymentStatus'] ?? e['data']?['paymentStatus'] ?? '')
              .toString()
              .toLowerCase();
      final title = (e['title'] ?? '').toString().toLowerCase();
      final eventType = (e['type'] ?? e['eventType'] ?? '')
          .toString()
          .toLowerCase();

      if (status == 'expired' ||
          e['isExpired'] == true ||
          e['data']?['isExpired'] == true) {
        isExpiredFromServer = true;
      } else if (status == 'cancelled' ||
          status == 'rejected' ||
          paymentStatus == 'failed' ||
          title.contains('cancelled') ||
          title.contains('rejected')) {
        isCancelled = true;
      } else if (status == 'completed' || title.contains('completed')) {
        isCompleted = true;
      } else if (paymentStatus == 'paid' ||
          eventType == 'payment_success' ||
          status == 'payment_done' ||
          e['adminApprovalStatus'] == 'payment_done') {
        isConfirmed = true;
      } else if (status == 'approved' ||
          status == 'awaiting_payment' ||
          title.contains('approved') ||
          eventType.contains('approved')) {
        isApproved = true;
      } else if (status == 'pending' || paymentStatus == 'pending') {
        isPending = true;
      }
    }

    // Status precedence: If cancelled, it is cancelled; If approved and not yet paid, it must be approved
    String overallStatus;
    if (isCancelled) {
      overallStatus = 'cancelled';
    } else if (isExpiredFromServer) {
      overallStatus = 'expired';
    } else if (isApproved && !isConfirmed) {
      overallStatus = 'approved';
    } else if (isConfirmed) {
      overallStatus = 'confirmed';
    } else if (isCompleted) {
      overallStatus = 'completed';
    } else {
      overallStatus = 'pending';
    }

    // Venue name
    String venueName =
        partyMap['venueName'] ??
        (partyMap['venue'] is Map ? partyMap['venue']['name'] : null) ??
        'Venue';
    if (venueName == 'Venue' || venueName.isEmpty) {
      for (final e in entries) {
        final vn =
            e['venueName'] ?? (e['venue'] is Map ? e['venue']['name'] : null);
        if (vn != null && vn.toString().isNotEmpty) {
          venueName = vn.toString();
          break;
        }
      }
    }

    // Guest count
    int guestCount = 5;
    final rawGuests =
        partyMap['guestCount'] ??
        partyMap['numberOfFriends'] ??
        partyMap['numberOfGuests'];
    if (rawGuests is num && rawGuests > 0) {
      guestCount = rawGuests.toInt();
    } else if (rawGuests != null) {
      final parsed = int.tryParse(rawGuests.toString());
      if (parsed != null && parsed > 0) guestCount = parsed;
    } else {
      for (final e in entries) {
        final gc =
            e['guestCount'] ??
            e['numberOfFriends'] ??
            e['numberOfGuests'] ??
            e['data']?['guestCount'];
        if (gc is num && gc > 0) {
          guestCount = gc.toInt();
          break;
        } else if (gc != null) {
          final parsed = int.tryParse(gc.toString());
          if (parsed != null && parsed > 0) {
            guestCount = parsed;
            break;
          }
        }
      }
    }

    // Timestamp & read status
    DateTime latestTime = DateTime.fromMillisecondsSinceEpoch(0);
    bool hasUnread = false;

    for (final e in entries) {
      final eId = e['id']?.toString() ?? '';
      final isRead =
          e['read'] == true ||
          e['isRead'] == true ||
          _localReadNotificationIds.contains(eId) ||
          ApiService.localReadRequestIds.contains(eId);
      if (!isRead) {
        hasUnread = true;
      }

      final rawDt = e['lastActivityAt'] ?? e['updatedAt'] ?? e['createdAt'];
      if (rawDt != null) {
        try {
          final dt = DateTime.parse(rawDt.toString()).toLocal();
          if (dt.isAfter(latestTime)) {
            latestTime = dt;
          }
        } catch (_) {}
      } else {
        final dt = _parseEventDateTime(
          e['partyDate'] ?? e['bookingDate'],
          e['startTime'] ?? e['time'],
        );
        if (dt != null && dt.isAfter(latestTime)) {
          latestTime = dt;
        }
      }
    }
    if (partyMap['lastActivityAt'] != null) {
      try {
        final dt = DateTime.parse(
          partyMap['lastActivityAt'].toString(),
        ).toLocal();
        if (dt.isAfter(latestTime)) latestTime = dt;
      } catch (_) {}
    }
    if (_localReadNotificationIds.contains('gp_$partyId') ||
        _localReadNotificationIds.contains(partyId) ||
        ApiService.localReadRequestIds.contains('gp_$partyId') ||
        ApiService.localReadRequestIds.contains(partyId)) {
      hasUnread = false;
    }
    if (latestTime.millisecondsSinceEpoch == 0) {
      latestTime = DateTime.now();
    }

    dynamic rawPartyDate =
        partyMap['partyDate'] ??
        partyMap['bookingDate'] ??
        partyMap['eventDateTime'];
    dynamic rawStartTime = partyMap['startTime'] ?? partyMap['time'];

    if (rawPartyDate == null || rawPartyDate.toString().trim().isEmpty) {
      for (final e in entries) {
        final d =
            e['partyDate'] ??
            e['bookingDate'] ??
            e['eventDateTime'] ??
            e['date'] ??
            e['data']?['partyDate'] ??
            e['data']?['bookingDate'] ??
            e['data']?['eventDateTime'] ??
            e['booking']?['bookingDate'] ??
            e['booking']?['partyDate'];
        if (d != null && d.toString().trim().isNotEmpty) {
          rawPartyDate = d;
          break;
        }
      }
    }
    if (rawStartTime == null || rawStartTime.toString().trim().isEmpty) {
      for (final e in entries) {
        final st =
            e['startTime'] ??
            e['time'] ??
            e['bookingTime'] ??
            e['data']?['startTime'] ??
            e['data']?['time'] ??
            e['data']?['bookingTime'] ??
            e['booking']?['startTime'] ??
            e['booking']?['time'];
        if (st != null && st.toString().trim().isNotEmpty) {
          rawStartTime = st;
          break;
        }
      }
    }

    final parsedEventDate = _parseEventDateTime(rawPartyDate, rawStartTime);

    // Format event date & time if available
    String formattedTimeStr = '';
    if (parsedEventDate != null) {
      const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final w = weekdayNames[parsedEventDate.weekday - 1];
      final m = monthNames[parsedEventDate.month - 1];
      final hour = parsedEventDate.hour % 12 == 0
          ? 12
          : parsedEventDate.hour % 12;
      final ampm = parsedEventDate.hour >= 12 ? 'PM' : 'AM';
      final minute = parsedEventDate.minute.toString().padLeft(2, '0');
      formattedTimeStr =
          ' on $w, ${parsedEventDate.day} $m at $hour:$minute $ampm';
    }

    // Construct Title, Body, Badge, and Actions
    String cardTitle = '👥 Group Party';
    String cardBody =
        'Your group party of $guestCount friends at $venueName$formattedTimeStr.';
    Color accentColor = const Color(0xFF7C3AED);
    String badgeText = 'BOOKING';
    String? actionButtonText;
    VoidCallback? onActionTap;

    // Prefer the server-persisted expiry flag (set once the cron sweep flips an
    // unpaid approved request to 'expired'); fall back to a client-side date-only
    // guess only when the server hasn't reported one yet (e.g. stale card).
    bool isExpired = isExpiredFromServer;
    if (!isExpired) {
      if (parsedEventDate != null &&
          DateTime.now().isAfter(
            parsedEventDate.add(const Duration(hours: 4)),
          )) {
        isExpired = true;
      }
    }

    // Distinguish Large Party (>20) vs Group Party (<=20)
    final bool isExplicitlySmall =
        entries.any((e) => e['isSmallGroupParty'] == true) ||
        partyMap['isSmallGroupParty'] == true;
    final bool isLargeParty =
        !isExplicitlySmall &&
        (guestCount > 20 ||
            partyMap['isLargePartyRequest'] == true ||
            partyMap['isLargeBooking'] == true ||
            partyMap['type'] == 'large_party_timeline');

    final String? cancelStatus =
        (partyMap['cancellationStatus'] ??
                partyMap['cancellation_status'] ??
                partyMap['refundStatus'] ??
                partyMap['refund_status'] ??
                entries.firstWhere(
                  (e) =>
                      e['cancellationStatus'] != null ||
                      e['cancellation_status'] != null ||
                      e['refundStatus'] != null,
                  orElse: () => <String, dynamic>{},
                )['cancellationStatus'] ??
                entries.firstWhere(
                  (e) =>
                      e['cancellationStatus'] != null ||
                      e['cancellation_status'] != null ||
                      e['refundStatus'] != null,
                  orElse: () => <String, dynamic>{},
                )['refundStatus'])
            ?.toString();
    final dynamic rawRefund =
        partyMap['cancellationRefundAmount'] ?? partyMap['refundAmount'];
    final double? refundAmt = rawRefund != null
        ? (rawRefund is num
              ? rawRefund.toDouble()
              : double.tryParse(rawRefund.toString()))
        : null;
    final String? rejectionReason =
        (partyMap['cancellationRejectionReason'] ??
                partyMap['rejectionReason'] ??
                partyMap['adminNotes'])
            ?.toString();

    if (isExpired) {
      accentColor = const Color(0xFF9CA3AF);
      badgeText = 'EXPIRED';
      cardTitle = isLargeParty
          ? 'Large Party Expired ⌛'
          : 'Group Party Expired ⌛';
      cardBody = 'Your party request at $venueName has expired.';
      actionButtonText = null;
      onActionTap = null;
    } else if (isLargeParty && cancelStatus == 'PENDING_ADMIN_REVIEW') {
      accentColor = const Color(0xFFF59E0B);
      badgeText = 'CANCELLATION REQUESTED';
      cardTitle = 'Cancellation Requested ⏳';
      cardBody =
          'Your cancellation request for $venueName is awaiting Lunara Admin review and refund calculation.';
      actionButtonText = null;
      onActionTap = null;
    } else if (overallStatus == 'confirmed') {
      if (isLargeParty && cancelStatus == 'REJECTED') {
        cardTitle = 'Cancellation Not Approved ℹ️';
        cardBody =
            'Your cancellation was not approved: ${rejectionReason ?? "Request not approved per policy"}. Your Large Party at $venueName remains confirmed!';
      } else {
        cardTitle = isLargeParty
            ? 'Large Party Confirmed! 🎉'
            : 'Group Party Confirmed! 🎉';
        cardBody =
            'Your party of $guestCount guests at $venueName$formattedTimeStr is fully confirmed. Get ready!';
      }
      badgeText = 'CONFIRMED';
      accentColor = const Color(0xFF10B981);
      actionButtonText = 'View Ticket';
      onActionTap = () {
        _markGroupPartyAsRead(entries);
        final venueMap = (partyMap['venue'] is Map)
            ? partyMap['venue'] as Map<dynamic, dynamic>
            : {'name': venueName};
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LargePartyTicketScreen(booking: partyMap, venue: venueMap),
          ),
        );
      };
    } else if (overallStatus == 'approved') {
      cardTitle = isLargeParty
          ? 'Large Party Approved! 💳'
          : 'Payment Required 💳';
      cardBody =
          'Action Required: Complete payment${totalAmount > 0 ? " of ₹${totalAmount.toInt()}" : ""} to confirm your party at $venueName.';
      badgeText = 'ACTION REQUIRED';
      accentColor = const Color(0xFFF59E0B);
      actionButtonText = 'Pay Now';
      onActionTap = () {
        _markGroupPartyAsRead(entries);
        _initiateLargePartyPayment(partyMap);
      };
    } else if (overallStatus == 'cancelled' ||
        cancelStatus == 'COMPLETED' ||
        cancelStatus == 'APPROVED' ||
        cancelStatus == 'REFUND_PROCESSING' ||
        cancelStatus == 'REFUND_PAID' ||
        cancelStatus == 'PENDING_PAYOUT') {
      final bool isRefundCompleted =
          cancelStatus == 'COMPLETED' ||
          cancelStatus == 'REFUND_PAID' ||
          partyMap['refundStatus'] == 'COMPLETED';
      final bool isRefundPendingPayout =
          cancelStatus == 'REFUND_PROCESSING' ||
          cancelStatus == 'PENDING_PAYOUT' ||
          partyMap['refundStatus'] == 'PENDING_PAYOUT';

      if (isRefundCompleted) {
        cardTitle = isLargeParty
            ? 'Large Party Refunded ✅'
            : 'Group Party Refunded ✅';
        badgeText = 'REFUND COMPLETED';
        accentColor = const Color(0xFF10B981);
        if (refundAmt != null && refundAmt > 0) {
          cardBody =
              'Your party at $venueName was cancelled and ₹${refundAmt.toInt()} refund has been paid successfully.';
        } else {
          cardBody =
              'Your party at $venueName was cancelled and refund has been completed.';
        }
      } else if (isRefundPendingPayout) {
        cardTitle = isLargeParty
            ? 'Refund Processing ⏳'
            : 'Group Party Refund Processing ⏳';
        badgeText = 'REFUND PROCESSING';
        accentColor = const Color(0xFFF59E0B);
        if (refundAmt != null && refundAmt > 0) {
          cardBody =
              'Cancellation approved. Your refund of ₹${refundAmt.toInt()} is being processed to your payout details.';
        } else {
          cardBody =
              'Cancellation approved. Your refund is being processed to your payout details.';
        }
      } else {
        cardTitle = isLargeParty
            ? 'Large Party Cancelled ❌'
            : 'Group Party Cancelled ❌';
        if (refundAmt != null && refundAmt > 0) {
          if (refundAmt <= 1500) {
            badgeText = 'REFUNDED TO WALLET';
            accentColor = const Color(0xFF10B981);
            cardBody =
                'Your party at $venueName was cancelled and ₹${refundAmt.toInt()} has been credited to your Lunara Wallet.';
          } else {
            badgeText = 'CANCELLED';
            accentColor = const Color(0xFFEF4444);
            cardBody =
                'Your party at $venueName was cancelled. A refund of ₹${refundAmt.toInt()} is being processed.';
          }
        } else {
          cardBody = 'Your party request at $venueName was cancelled.';
          badgeText = 'CANCELLED';
          accentColor = const Color(0xFFEF4444);
        }
      }
    } else {
      // ── Pending state: waiting for admin approval (or admin has approved but no price set yet)
      // NEVER show a Pay Now button when amount is 0 — that means admin hasn't set a price.
      final bool hasPendingPrice = totalAmount > 0;

      if (isLargeParty || !hasPendingPrice) {
        // Large party OR no price set yet → always show "Pending Approval" (no pay button)
        cardTitle = isLargeParty
            ? 'Large Party Submitted ⏳'
            : 'Group Party Submitted ⏳';
        cardBody =
            'Your request for $guestCount guests at $venueName is pending admin approval. You\'ll be notified once it\'s reviewed.';
        badgeText = 'PENDING APPROVAL';
        accentColor = const Color(0xFF8B5CF6);
        actionButtonText = null;
        onActionTap = null;
      } else {
        // Small group party where admin has set a price — payment required
        cardTitle = 'Payment Required 💳';
        cardBody =
            'Action Required: Complete payment of ₹${totalAmount.toInt()} to confirm your group party at $venueName.';
        badgeText = 'PAYMENT REQUIRED';
        accentColor = const Color(0xFFF59E0B);
        actionButtonText = 'Pay Now';
        onActionTap = () {
          _markGroupPartyAsRead(entries);
          _initiateLargePartyPayment(partyMap);
        };
      }
    }

    List<NotificationAction>? actions;
    if (!isExpired && actionButtonText != null && onActionTap != null) {
      final bool isProcessingPay =
          (actionButtonText == 'Pay Now' &&
          _processingPaymentBookingId == partyId);
      actions = [
        NotificationAction(
          label: isProcessingPay ? 'Processing...' : actionButtonText,
          onTap: isProcessingPay ? () {} : onActionTap,
          isPrimary: true,
          isLoading: isProcessingPay,
          icon: actionButtonText == 'Pay Now'
              ? Icons.payment_rounded
              : Icons.confirmation_number_rounded,
        ),
      ];

      if (overallStatus == 'confirmed') {
        final dateStr = parsedEventDate != null
            ? '${parsedEventDate.year}-${parsedEventDate.month.toString().padLeft(2, '0')}-${parsedEventDate.day.toString().padLeft(2, '0')}'
            : (rawPartyDate?.toString() ?? '');
        final timeStr = parsedEventDate != null
            ? LunaraDateFormatter.normalizeTimeTo12Hour(
                '${parsedEventDate.hour}:${parsedEventDate.minute.toString().padLeft(2, '0')}',
              )
            : (rawStartTime?.toString() ?? '');
        final cleanPartyId = ApiService.cleanBookingId(partyId);

        actions.add(
          NotificationAction(
            label: 'Cancel Booking',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            onTap: () {
              BookingCancellationDialog.show(
                context,
                bookingId: cleanPartyId.isNotEmpty ? cleanPartyId : partyId,
                isGroupParty: true,
                initialVenueName: venueName,
                initialDate: dateStr,
                initialTime: timeStr,
                initialAmountPaid: totalAmount,
                onCancelled: () {
                  _optimisticallyMarkBookingCancelled(
                    cleanPartyId.isNotEmpty ? cleanPartyId : partyId,
                  );
                  ApiService.clearBookingCache();
                  _loadFeed(showLoader: false, forceRefresh: true);
                },
              );
            },
          ),
        );
      }
    }

    final String? venuePhoto =
        _extractVenuePhoto(partyMap['venue']) ?? _extractVenuePhoto(partyMap);

    return UnifiedNotificationItem(
      id: 'group_party_timeline_$partyId',
      category: 'booking',
      title: cardTitle,
      body: cardBody,
      createdAt: latestTime,
      timeAgo: _formatTimeAgo(latestTime.toIso8601String()),
      isRead:
          (badgeText == 'ACTION REQUIRED' || badgeText == 'PAYMENT REQUIRED')
          ? false
          : !hasUnread,
      isExpired: isExpired,
      badgeText: badgeText,
      accentColor: accentColor,
      categoryIcon: Icons.groups_rounded,
      avatarUrl: venuePhoto,
      actionButtonText: actionButtonText,
      onActionTap: onActionTap,
      actions: isExpired ? null : actions,
      rawData: partyMap,
    );
  }

  void _markGroupPartyAsRead(List<Map<String, dynamic>> entries) {
    for (final e in entries) {
      final eId = e['id']?.toString() ?? '';
      if (eId.isNotEmpty) {
        ApiService.localReadRequestIds.add(eId);
        ApiService.localReadNotificationIds.add(eId);
        ApiService.markNotificationRead(eId);
      }
    }
    ApiService.saveLocalReadRequestIds();
    ApiService.saveLocalReadNotificationIds();
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Authoritative Solo & Table Booking Smart Card (1 Booking = 1 Card)
  // ─────────────────────────────────────────────────────────────────────────────
  UnifiedNotificationItem? _buildAuthoritativeSoloBookingCard(
    String bookingId,
    List<Map<String, dynamic>> entries,
    String currentUserId,
  ) {
    if (entries.isEmpty) return null;
    final cleanBId = bookingId.toLowerCase();
    if (cleanBId.startsWith('party_plan') ||
        cleanBId.startsWith('pp_') ||
        cleanBId.startsWith('strangers_meet') ||
        cleanBId.startsWith('sm_') ||
        cleanBId.startsWith('group_party') ||
        cleanBId.startsWith('gp_')) {
      return null;
    }
    for (final e in entries) {
      if (_isPartyPlanItem(e) || _isStrangerMeetItem(e)) return null;
    }

    Map<String, dynamic> bookingMap = {};
    for (final e in entries) {
      if (e['data'] is Map &&
          (e['data']['type'] == 'venue_booking_timeline' ||
              e['data']['bookingId'] != null)) {
        bookingMap = Map<String, dynamic>.from(e['data']);
        break;
      }
      if (e['booking'] is Map) {
        bookingMap = Map<String, dynamic>.from(e['booking']);
        break;
      }
    }
    if (bookingMap.isEmpty) {
      bookingMap = Map<String, dynamic>.from(entries.first);
      if (bookingMap['data'] is Map) {
        bookingMap.addAll(Map<String, dynamic>.from(bookingMap['data']));
      }
    }

    // Extract total amount
    double totalAmount = 0.0;
    for (final e in entries) {
      final rawAmt =
          e['totalAmount'] ??
          e['amount'] ??
          e['booking']?['totalAmount'] ??
          e['data']?['totalAmount'] ??
          e['data']?['amount'];
      if (rawAmt is num && rawAmt > 0) {
        totalAmount = rawAmt.toDouble();
        break;
      } else if (rawAmt != null) {
        final parsed = double.tryParse(rawAmt.toString());
        if (parsed != null && parsed > 0) {
          totalAmount = parsed;
          break;
        }
      }
    }
    if (totalAmount > 0) {
      bookingMap['totalAmount'] = totalAmount;
    }

    // Extract venue name and date/time
    String venueName =
        bookingMap['venueName'] ?? bookingMap['venue']?['name'] ?? 'Venue';
    for (final e in entries) {
      final vName =
          e['venueName'] ??
          e['venue']?['name'] ??
          e['data']?['venueName'] ??
          e['booking']?['venue']?['name'];
      if (vName != null && vName.toString().isNotEmpty) {
        venueName = vName.toString();
        break;
      }
    }

    String dateStr = bookingMap['bookingDate']?.toString() ?? '';
    String timeStr =
        bookingMap['startTime']?.toString() ??
        bookingMap['time']?.toString() ??
        '';
    for (final e in entries) {
      final d =
          e['bookingDate'] ??
          e['data']?['bookingDate'] ??
          e['booking']?['bookingDate'];
      final t =
          e['startTime'] ??
          e['time'] ??
          e['bookingTime'] ??
          e['data']?['startTime'] ??
          e['booking']?['startTime'];
      if (d != null && d.toString().isNotEmpty && dateStr.isEmpty) {
        dateStr = d.toString();
      }
      if (t != null && t.toString().isNotEmpty && timeStr.isEmpty) {
        timeStr = t.toString();
      }
    }
    if (timeStr.isNotEmpty) {
      timeStr = LunaraDateFormatter.normalizeTimeTo12Hour(timeStr);
    }

    final dynamic rawSoloGuests =
        bookingMap['numberOfGuests'] ?? bookingMap['guestCount'] ?? 1;
    int guestCount = rawSoloGuests is num
        ? rawSoloGuests.toInt()
        : (int.tryParse(rawSoloGuests.toString()) ?? 1);
    for (final e in entries) {
      final g =
          e['numberOfGuests'] ??
          e['guestCount'] ??
          e['data']?['guestCount'] ??
          e['booking']?['numberOfGuests'];
      if (g is num && g > 0) {
        guestCount = g.toInt();
        break;
      } else if (g != null) {
        final parsed = int.tryParse(g.toString());
        if (parsed != null && parsed > 0) {
          guestCount = parsed;
          break;
        }
      }
    }

    String ticketCode =
        (bookingMap['ticketCode'] ?? bookingMap['ticketId'] ?? '').toString();
    for (final e in entries) {
      final tc =
          e['ticketCode'] ??
          e['ticketId'] ??
          e['data']?['ticketCode'] ??
          e['booking']?['ticketCode'];
      if (tc != null && tc.toString().isNotEmpty) {
        ticketCode = tc.toString();
        break;
      }
    }

    // Status evaluation
    bool isConfirmed = false;
    bool isCancelled = false;
    bool isCompleted = false;
    bool isPending = false;
    bool isRefunded = false;

    for (final e in entries) {
      final status =
          (e['status'] ?? e['bookingStatus'] ?? e['data']?['status'] ?? '')
              .toString()
              .toLowerCase();
      final paymentStatus =
          (e['paymentStatus'] ?? e['data']?['paymentStatus'] ?? '')
              .toString()
              .toLowerCase();
      final title = (e['title'] ?? '').toString().toLowerCase();
      final eventType = (e['eventType'] ?? e['type'] ?? '')
          .toString()
          .toLowerCase();

      if (status == 'cancelled' ||
          eventType == 'booking_cancelled' ||
          title.contains('cancelled')) {
        isCancelled = true;
        if (paymentStatus == 'refunded' || e['refundAmount'] != null) {
          isRefunded = true;
        }
      } else if (status == 'completed' || title.contains('completed')) {
        isCompleted = true;
      } else if (paymentStatus == 'paid' ||
          status == 'confirmed' ||
          eventType == 'booking_confirmed' ||
          eventType == 'booking_paynow' ||
          eventType == 'payment_success') {
        isConfirmed = true;
      } else if (status == 'pending' ||
          paymentStatus == 'pending' ||
          eventType == 'booking_pending_payment') {
        isPending = true;
      }
    }

    if (isCancelled) {
      isConfirmed = false;
      isPending = false;
    } else if (isConfirmed) {
      isPending = false;
    } else if (isPending && totalAmount <= 0) {
      isConfirmed = true;
      isPending = false;
    }

    // Extract refund amount and refund percentage
    double refundAmount = 0.0;
    int? refundPercentage;
    for (final e in entries) {
      final rawRefund =
          e['refundAmount'] ??
          e['data']?['refundAmount'] ??
          e['booking']?['refundAmount'];
      if (rawRefund is num && rawRefund > 0) {
        refundAmount = rawRefund.toDouble();
        break;
      } else if (rawRefund != null) {
        final parsed = double.tryParse(rawRefund.toString());
        if (parsed != null && parsed > 0) {
          refundAmount = parsed;
          break;
        }
      }
    }
    for (final e in entries) {
      final rawPct =
          e['refundPercentage'] ??
          e['data']?['refundPercentage'] ??
          e['booking']?['refundPercentage'];
      if (rawPct is num && rawPct > 0) {
        refundPercentage = rawPct.toInt();
        break;
      } else if (rawPct != null) {
        final parsed = int.tryParse(rawPct.toString());
        if (parsed != null && parsed > 0) {
          refundPercentage = parsed;
          break;
        }
      }
    }

    if (refundAmount <= 0 && isRefunded && totalAmount > 0) {
      final pct = refundPercentage ?? 100;
      refundAmount = (totalAmount * pct / 100.0);
    }

    final int effectivePct =
        refundPercentage ??
        ((totalAmount > 0 && refundAmount > 0)
            ? ((refundAmount / totalAmount) * 100).round()
            : 100);

    final bool isSolo = guestCount <= 1;
    final String bookingTypeLabel = isSolo
        ? 'Solo Booking'
        : 'Table Booking ($guestCount Guests)';
    String title = '$bookingTypeLabel at $venueName 🎟';
    String body = isConfirmed
        ? 'Your reservation at $venueName is fully confirmed. Digital ticket is ready!'
        : (isCancelled
              ? ((refundAmount > 0 || isRefunded)
                    ? 'Your booking was cancelled. $effectivePct% (₹${refundAmount.toStringAsFixed(0)}) refunded to your Lunara Wallet.'
                    : 'Your booking was cancelled.')
              : (isCompleted
                    ? 'Hope you enjoyed your experience at $venueName!'
                    : 'Complete payment of ₹${totalAmount.toStringAsFixed(0)} to secure your table reservation.'));

    String badge = 'CONFIRMED';
    Color accentColor = const Color(0xFF7C3AED);
    IconData icon = Icons.confirmation_number_rounded;

    if (isCancelled) {
      badge = 'CANCELLED';
      accentColor = const Color(0xFFEF4444);
      icon = Icons.cancel_rounded;
    } else if (isCompleted) {
      badge = 'COMPLETED';
      accentColor = const Color(0xFF10B981);
      icon = Icons.check_circle_rounded;
    } else if (isPending) {
      badge = 'PAYMENT PENDING';
      accentColor = const Color(0xFFF59E0B);
      icon = Icons.payment_rounded;
    }

    List<NotificationAction> actionsList = [];
    if (isConfirmed && !isCancelled) {
      actionsList.add(
        NotificationAction(
          label: 'View Ticket',
          icon: Icons.confirmation_number_rounded,
          isPrimary: true,
          onTap: () {
            final venueMap = bookingMap['venue'] is Map
                ? bookingMap['venue']
                : {'name': venueName, 'id': bookingMap['venueId']};
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DigitalTicketScreen(
                  venue: venueMap,
                  date: dateStr,
                  time: timeStr,
                  table: isSolo ? 'Solo Entry' : 'Standard Table',
                  guests: guestCount.toString(),
                  package: isSolo ? 'Solo Entry' : 'Standard Table',
                  totalPrice: totalAmount > 0
                      ? '₹${totalAmount.toStringAsFixed(0)}'
                      : 'FREE (₹0)',
                  ticketId: ticketCode.isNotEmpty ? ticketCode : bookingId,
                  ticketUrl: bookingMap['ticketUrl']?.toString(),
                  status: 'CONFIRMED',
                  booking: {
                    ...bookingMap,
                    'id': bookingId,
                    'bookingId': bookingId,
                    'venue': venueMap,
                    'isSolo': isSolo,
                    'goingMode': isSolo ? 'solo' : 'party_request',
                    'bookingType': isSolo ? 'solo' : 'venue_booking',
                    'category': isSolo ? 'solo' : 'venue_booking',
                    'totalAmount': totalAmount,
                    'paymentStatus': 'paid',
                    'status': 'CONFIRMED',
                    'tablePackage': isSolo ? 'Solo Entry' : 'Standard Table',
                    'numberOfGuests': guestCount,
                    'bookingDate': dateStr,
                    'startTime': timeStr,
                    'user': ApiService.cachedCurrentUser,
                  },
                  user: ApiService.cachedCurrentUser,
                ),
              ),
            );
          },
        ),
      );

      actionsList.add(
        NotificationAction(
          label: 'Cancel Booking',
          icon: Icons.cancel_outlined,
          isPrimary: false,
          onTap: () {
            BookingCancellationDialog.show(
              context,
              bookingId: bookingId,
              isGroupParty: false,
              initialVenueName: venueName,
              initialDate: dateStr,
              initialTime: timeStr,
              initialAmountPaid: totalAmount,
              onCancelled: () {
                _optimisticallyMarkBookingCancelled(
                  bookingId,
                  refundAmount: refundAmount > 0 ? refundAmount : null,
                  refundPercentage: effectivePct,
                );
                ApiService.clearBookingCache();
                _loadFeed(showLoader: false, forceRefresh: true);
              },
            );
          },
        ),
      );
    } else if (isPending && !isCancelled) {
      final isProcessingPayment = _processingPaymentBookingId == bookingId;
      actionsList.add(
        NotificationAction(
          label: isProcessingPayment ? 'Processing...' : 'Pay Now',
          icon: Icons.credit_card_rounded,
          isPrimary: true,
          isLoading: isProcessingPayment,
          onTap: isProcessingPayment
              ? () {}
              : () => _initiatePendingBookingPayment(bookingMap),
        ),
      );
    } else if (isCancelled &&
        (isRefunded || refundAmount > 0 || totalAmount > 0)) {
      actionsList.add(
        NotificationAction(
          label: 'View Wallet',
          icon: Icons.account_balance_wallet_rounded,
          isPrimary: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
          ),
        ),
      );
    }

    DateTime latestCreatedAt = DateTime.fromMillisecondsSinceEpoch(0);
    bool hasUnread = false;
    for (final e in entries) {
      final eId = e['id']?.toString() ?? '';
      final isRead =
          e['read'] == true ||
          e['isRead'] == true ||
          _localReadNotificationIds.contains(eId) ||
          ApiService.localReadRequestIds.contains(eId);
      if (!isRead) hasUnread = true;

      final rawDt = e['lastActivityAt'] ?? e['updatedAt'] ?? e['createdAt'];
      if (rawDt != null) {
        try {
          final dt = DateTime.parse(rawDt.toString()).toLocal();
          if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
        } catch (_) {}
      }
    }
    if (bookingMap['lastActivityAt'] != null) {
      try {
        final dt = DateTime.parse(
          bookingMap['lastActivityAt'].toString(),
        ).toLocal();
        if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
      } catch (_) {}
    }
    if (latestCreatedAt.millisecondsSinceEpoch == 0) {
      latestCreatedAt = _parseDateTime(
        entries.first['createdAt'] ?? entries.first['updatedAt'],
      );
    }
    if (_localReadNotificationIds.contains(
          'venue_booking_timeline_$bookingId',
        ) ||
        _localReadNotificationIds.contains(bookingId) ||
        ApiService.localReadRequestIds.contains(
          'venue_booking_timeline_$bookingId',
        ) ||
        ApiService.localReadRequestIds.contains(bookingId)) {
      hasUnread = false;
    }
    if (badge == 'ACTION REQUIRED' || badge == 'PAYMENT PENDING') {
      hasUnread = true;
    }
    final timeAgo = _formatTimeAgo(latestCreatedAt);

    return UnifiedNotificationItem(
      id: 'venue_booking_timeline_$bookingId',
      category: 'booking',
      title: title,
      body: body,
      createdAt: latestCreatedAt,
      timeAgo: timeAgo,
      isRead: !hasUnread,
      isExpired: false,
      badgeText: badge,
      accentColor: accentColor,
      categoryIcon: icon,
      avatarUrl:
          _extractVenuePhoto(bookingMap['venue']) ??
          _extractVenuePhoto(bookingMap) ??
          bookingMap['venueImageUrl']?.toString(),
      actions: actionsList.isNotEmpty ? actionsList : null,
      rawData: {
        ...bookingMap,
        'id': bookingId,
        'bookingId': bookingId,
        'venueName': venueName,
        'bookingDate': dateStr,
        'startTime': timeStr,
        'totalAmount': totalAmount,
        'numberOfGuests': guestCount,
        'ticketCode': ticketCode,
      },
      statusSummary: isCancelled
          ? 'Cancelled'
          : (isConfirmed ? 'Confirmed' : 'Payment Pending'),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build Authoritative Upcoming Night Smart Card (1 Night = 1 Card)
  // ─────────────────────────────────────────────────────────────────────────────
  UnifiedNotificationItem? _buildAuthoritativeUpcomingNightCard(
    String nightId,
    List<Map<String, dynamic>> entries,
    String currentUserId,
  ) {
    int getProgressScore(Map<String, dynamic> e) {
      final s = (e['stage'] ??
              e['status'] ??
              e['data']?['stage'] ??
              e['data']?['status'] ??
              e['metadata']?['stage'] ??
              e['metadata']?['status'] ??
              '')
          .toString()
          .toUpperCase();
      if (s == 'FULLY_BOOKED' || s == 'CONFIRMED') return 5;
      if (s == 'WAITING_FOR_PAYMENT' || s == 'PAYMENT_PENDING') return 4;
      if (s == 'MATCHED' || s == 'ACCEPTED') return 3;
      if (s == 'INVITE_SENT' || s == 'PENDING' || s == 'INVITE_RECEIVED') return 2;
      return 1;
    }

    final sortedEntries = List<Map<String, dynamic>>.from(entries)
      ..sort((a, b) => getProgressScore(b).compareTo(getProgressScore(a)));

    Map<String, dynamic> metadata = {};
    Map<String, dynamic> rawItem = sortedEntries.first;

    for (final e in sortedEntries) {
      if (e['metadata'] is Map && (e['metadata'] as Map).isNotEmpty) {
        metadata.addAll(Map<String, dynamic>.from(e['metadata']));
      }
      if (e['data'] is Map && (e['data'] as Map).isNotEmpty) {
        metadata.addAll(Map<String, dynamic>.from(e['data']));
      }
      if (e['id']?.toString().startsWith('upcoming_night_timeline_') == true) {
        rawItem = e;
      }
    }

    final String requestId =
        (metadata['requestId'] ??
                rawItem['requestId'] ??
                rawItem['data']?['requestId'] ??
                (rawItem['id']?.toString().startsWith(
                          'upcoming_night_timeline_',
                        ) ==
                        false
                    ? rawItem['id']
                    : null) ??
                nightId)
            .toString();
    final String matchId =
        (metadata['matchId'] ??
                rawItem['matchId'] ??
                rawItem['data']?['matchId'] ??
                '')
            .toString();
    final String targetRequestId = requestId.isNotEmpty
        ? requestId
        : (matchId.isNotEmpty ? matchId : nightId);
    final String targetMatchId = matchId.isNotEmpty
        ? matchId
        : (requestId.isNotEmpty ? requestId : nightId);

    final String status =
        (metadata['status'] ?? rawItem['status'] ?? 'INVITE_SENT')
            .toString()
            .toUpperCase();
    final String stage =
        (metadata['stage'] ?? rawItem['stage'] ?? 'INVITE_SENT')
            .toString()
            .toUpperCase();
    final String cancellationStatus =
        (metadata['cancellationStatus'] ??
                rawItem['cancellationStatus'] ??
                rawItem['data']?['cancellationStatus'] ??
                'NONE')
            .toString()
            .toUpperCase();
    final String cancelledBy =
        (metadata['cancelledBy'] ??
                rawItem['cancelledBy'] ??
                rawItem['data']?['cancelledBy'] ??
                '')
            .toString();

    // If request is cancelled, expired, or declined and not an active confirmed match, remove from live feed
    if (matchId.isEmpty) {
      if (status == 'EXPIRED' ||
          status == 'DECLINED' ||
          status == 'REJECTED' ||
          status == 'CANCELLED' ||
          stage == 'EXPIRED' ||
          stage == 'CANCELLED' ||
          stage == 'DECLINED') {
        return null;
      }
      final rawExpiresAt = metadata['expiresAt'] ?? rawItem['expiresAt'] ?? rawItem['data']?['expiresAt'];
      if (rawExpiresAt != null) {
        final exp = DateTime.tryParse(rawExpiresAt.toString());
        if (exp != null && exp.isBefore(DateTime.now())) {
          return null;
        }
      }
    }

    final String hostId =
        (metadata['hostId'] ??
                rawItem['hostId'] ??
                rawItem['actorUserId'] ??
                rawItem['senderId'] ??
                '')
            .toString();
    final String partnerId =
        (metadata['partnerId'] ??
                rawItem['partnerId'] ??
                rawItem['recipientUserId'] ??
                '')
            .toString();
    final String myId =
        (currentUserId.isNotEmpty
                ? currentUserId
                : ApiService.currentUserId ?? '')
            .toString();

    bool isCurrentUserHost = false;
    if (metadata['isHost'] != null) {
      isCurrentUserHost = metadata['isHost'] == true;
    } else if (rawItem['isHost'] != null) {
      isCurrentUserHost = rawItem['isHost'] == true;
    } else if (metadata['userRole'] != null) {
      isCurrentUserHost =
          metadata['userRole'].toString().toUpperCase() == 'HOST';
    } else if (rawItem['userRole'] != null) {
      isCurrentUserHost =
          rawItem['userRole'].toString().toUpperCase() == 'HOST';
    } else if (myId.isNotEmpty) {
      if (hostId.isNotEmpty && hostId == myId) {
        isCurrentUserHost = true;
      } else if (partnerId.isNotEmpty && partnerId == myId) {
        isCurrentUserHost = false;
      } else if (rawItem['actorUserId'] != null &&
          rawItem['actorUserId'].toString() == myId) {
        isCurrentUserHost = true;
      } else if (rawItem['recipientUserId'] != null &&
          rawItem['recipientUserId'].toString() == myId) {
        isCurrentUserHost = false;
      }
    } else {
      isCurrentUserHost = false;
    }

    final Map<String, dynamic> partnerData = metadata['partner'] is Map
        ? Map<String, dynamic>.from(metadata['partner'])
        : (rawItem['partner'] is Map
              ? Map<String, dynamic>.from(rawItem['partner'])
              : (rawItem['sender'] is Map
                    ? Map<String, dynamic>.from(rawItem['sender'])
                    : <String, dynamic>{}));

    final String partnerName =
        partnerData['name']?.toString() ??
        partnerData['firstName']?.toString() ??
        rawItem['senderName']?.toString() ??
        rawItem['otherUserName']?.toString() ??
        (isCurrentUserHost ? 'Night Partner' : 'Host');
    final String? partnerPhoto =
        partnerData['photo']?.toString() ??
        partnerData['profilePhotoUrl']?.toString() ??
        partnerData['profileImageUrl']?.toString() ??
        rawItem['senderImage']?.toString() ??
        rawItem['otherUserPhoto']?.toString();

    final Map<String, dynamic> eventData = metadata['event'] is Map
        ? Map<String, dynamic>.from(metadata['event'])
        : (rawItem['event'] is Map
              ? Map<String, dynamic>.from(rawItem['event'])
              : <String, dynamic>{});

    final String eventName =
        eventData['name']?.toString() ??
        eventData['title']?.toString() ??
        metadata['eventName']?.toString() ??
        metadata['title']?.toString() ??
        rawItem['eventName']?.toString() ??
        rawItem['title']?.toString() ??
        '';

    final String venueName =
        eventData['venueName']?.toString() ??
        metadata['venue']?['name']?.toString() ??
        metadata['venueName']?.toString() ??
        rawItem['venueName']?.toString() ??
        'Upcoming Night Venue';

    final String displayTitle = eventName.isNotEmpty && eventName != venueName
        ? '$eventName • $venueName'
        : venueName;

    final String dateStr =
        eventData['date']?.toString() ??
        metadata['date']?.toString() ??
        metadata['eventDate']?.toString() ??
        rawItem['date']?.toString() ??
        rawItem['eventDate']?.toString() ??
        'Tonight';
    final String timeStr =
        eventData['time']?.toString() ??
        metadata['time']?.toString() ??
        metadata['eventTime']?.toString() ??
        rawItem['time']?.toString() ??
        rawItem['eventTime']?.toString() ??
        '8:00 PM';
    final String? venuePhoto =
        eventData['coverImageUrl']?.toString() ??
        metadata['coverImageUrl']?.toString() ??
        metadata['venue']?['coverImageUrl']?.toString() ??
        _extractVenuePhoto(metadata['venue']) ??
        _extractVenuePhoto(rawItem);

    final String? ticketId =
        metadata['ticketId']?.toString() ?? rawItem['ticketCode']?.toString();
    final String? chatId =
        metadata['chatId']?.toString() ?? rawItem['conversationId']?.toString();

    final bool isCancellationRequested = cancellationStatus == 'REQUESTED';
    final bool isCanceller =
        isCancellationRequested &&
        (cancelledBy.isNotEmpty ? cancelledBy == myId : false);
    final bool isCancellationRecipient =
        isCancellationRequested && !isCanceller;

    Color accentColor = LunaraTheme.electricViolet;
    String badgeText = 'UPCOMING NIGHT';
    String cardTitle = 'Upcoming Night 🌙';
    String cardBody = 'Event at $displayTitle on $dateStr • $timeStr';
    List<NotificationAction> actionsList = [];

    DateTime latestTime = _parseDateTime(
      rawItem['createdAt'] ?? rawItem['updatedAt'],
    );

    if (status == 'CANCELLED' || stage == 'CANCELLED') {
      accentColor = const Color(0xFFEF4444);
      badgeText = 'CANCELLED';
      cardTitle = 'Upcoming Night Cancelled ❌';
      cardBody = 'The upcoming night at $venueName was cancelled.';
    } else if (isCancellationRequested) {
      if (isCancellationRecipient) {
        accentColor = const Color(0xFFEF4444);
        badgeText = 'ACTION REQUIRED';
        cardTitle = 'Cancellation Request Received ⚠️';
        final reason =
            (metadata['cancellationReason'] ??
                    rawItem['cancellationReason'] ??
                    'Change of plans')
                .toString();
        cardBody =
            '$partnerName requested to cancel Upcoming Night at $displayTitle. Reason: "$reason". Please confirm to process refund or keep active.';

        final acceptCancelKey = 'accept_cancel_$targetMatchId';
        final rejectCancelKey = 'reject_cancel_$targetMatchId';
        final isAcceptingCancel = _activeActionKeys.contains(acceptCancelKey);
        final isRejectingCancel = _activeActionKeys.contains(rejectCancelKey);

        actionsList.add(
          NotificationAction(
            label: isAcceptingCancel ? 'Processing...' : 'Confirm & Refund',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            isLoading: isAcceptingCancel,
            onTap: (isAcceptingCancel || isRejectingCancel)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(acceptCancelKey));
                    try {
                      final res = await ApiService.cancelUpcomingNight(
                        targetId: targetMatchId,
                        action: 'approve',
                      );
                      if (res != null && res['success'] == true) {
                        _optimisticallyMarkBookingCancelled(targetMatchId);
                        _loadFeed(showLoader: false, forceRefresh: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Upcoming night cancelled and refunded to wallet.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              res?['message'] ??
                                  'Could not process cancellation.',
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(
                          () => _activeActionKeys.remove(acceptCancelKey),
                        );
                      }
                    }
                  },
          ),
        );

        actionsList.add(
          NotificationAction(
            label: isRejectingCancel ? 'Processing...' : 'Keep Active',
            icon: Icons.close_rounded,
            isPrimary: false,
            isLoading: isRejectingCancel,
            onTap: (isAcceptingCancel || isRejectingCancel)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(rejectCancelKey));
                    try {
                      final res = await ApiService.cancelUpcomingNight(
                        targetId: targetMatchId,
                        action: 'reject',
                      );
                      if (res != null && res['success'] == true) {
                        _loadFeed(showLoader: false, forceRefresh: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Cancellation declined. Event remains confirmed.',
                            ),
                            backgroundColor: Colors.blueGrey,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(
                          () => _activeActionKeys.remove(rejectCancelKey),
                        );
                      }
                    }
                  },
          ),
        );
      } else {
        accentColor = const Color(0xFFF59E0B);
        badgeText = 'PENDING';
        cardTitle = 'Cancellation Requested ⏳';
        cardBody =
            'Waiting for $partnerName to confirm cancellation of Upcoming Night at $displayTitle.';
      }
    } else if (stage == 'FULLY_BOOKED' || status == 'CONFIRMED') {
      accentColor = const Color(0xFF10B981);
      badgeText = 'CONFIRMED';
      cardTitle = 'Upcoming Night Confirmed! 🎉';
      cardBody =
          'You and $partnerName are set for $displayTitle on $dateStr • $timeStr! Ticket is locked.';

      if (ticketId != null && ticketId.isNotEmpty) {
        actionsList.add(
          NotificationAction(
            label: 'View Ticket',
            icon: Icons.confirmation_number_rounded,
            isPrimary: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DigitalTicketScreen(
                    venue: {'name': venueName, 'coverImageUrl': venuePhoto},
                    date: dateStr,
                    time: timeStr,
                    guests: '2',
                    ticketId: ticketId,
                  ),
                ),
              );
            },
          ),
        );
      }

      if (chatId != null && chatId.isNotEmpty) {
        actionsList.add(
          NotificationAction(
            label: 'Open Chat',
            icon: Icons.chat_bubble_outline_rounded,
            isPrimary: false,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    user: {
                      'id': partnerData['id'] ?? '',
                      'firstName': partnerName,
                      'profilePhotoUrl': partnerPhoto,
                      'conversationId': chatId,
                    },
                  ),
                ),
              );
            },
          ),
        );
      }

      actionsList.add(
        NotificationAction(
          label: 'Cancel Event',
          icon: Icons.cancel_outlined,
          isPrimary: false,
          color: Colors.red[400],
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1035),
                title: const Text(
                  'Cancel Upcoming Night?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: const Text(
                  'Are you sure you want to cancel this Upcoming Night booking? Any refundable amount will be credited to your Lunara Wallet.',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Keep Booking',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    child: const Text(
                      'Confirm Cancel',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            );

            if (confirm == true) {
              final res = await ApiService.cancelUpcomingNight(
                targetId: targetMatchId,
                reason: 'User requested cancellation',
              );
              if (res != null && res['success'] == true) {
                _loadFeed(showLoader: false, forceRefresh: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cancellation request submitted.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      res?['message'] ??
                          'Could not cancel upcoming night. Please contact support.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }
          },
        ),
      );
    } else if (stage == 'WAITING_FOR_PAYMENT' ||
        status == 'ACCEPTED' ||
        status == 'MATCHED') {
      accentColor = const Color(0xFFF59E0B);
      badgeText = isCurrentUserHost ? 'ACTION REQUIRED' : 'WAITING FOR HOST';
      cardTitle = isCurrentUserHost
          ? 'Invite Accepted! 💳'
          : 'Waiting for Confirmation 🎉';
      cardBody = isCurrentUserHost
          ? '$partnerName accepted your invite for $displayTitle! Complete payment to lock your match.'
          : 'You accepted the invite! Waiting for host ($partnerName) to complete booking payment.';

      if (isCurrentUserHost) {
        actionsList.add(
          NotificationAction(
            label: 'Pay & Lock',
            icon: Icons.payment_rounded,
            isPrimary: true,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => UpcomingNightHostConfirmDialog(
                  matchId: targetMatchId,
                  partnerName: partnerName,
                  partnerPhoto: partnerPhoto,
                  venueName: venueName,
                  date: dateStr,
                  time: timeStr,
                ),
              );
            },
          ),
        );
      }

      actionsList.add(
        NotificationAction(
          label: 'Cancel',
          icon: Icons.cancel_outlined,
          isPrimary: false,
          color: Colors.red[400],
          onTap: () async {
            final res = await ApiService.cancelUpcomingNight(
              targetId: targetMatchId,
              reason: 'Cancelled before booking',
            );
            if (res != null && res['success'] == true) {
              _loadFeed(showLoader: false, forceRefresh: true);
            }
          },
        ),
      );
    } else {
      // stage == 'INVITE_SENT' or PENDING
      if (!isCurrentUserHost) {
        accentColor = LunaraTheme.electricViolet;
        badgeText = 'INVITE';
        cardTitle = 'Invite for Party Event🌙';
        cardBody =
            '$partnerName invited you to join for $displayTitle on $dateStr • $timeStr!';

        final acceptKey = 'accept_np_$targetRequestId';
        final declineKey = 'decline_np_$targetRequestId';
        final isAccepting = _activeActionKeys.contains(acceptKey);
        final isDeclining = _activeActionKeys.contains(declineKey);

        actionsList.add(
          NotificationAction(
            label: isAccepting ? 'Accepting...' : 'Accept',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            isLoading: isAccepting,
            onTap: (isAccepting || isDeclining)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(acceptKey));
                    try {
                      final res =
                          await ApiService.respondToNightPartnerRequestDetailed(
                            requestId: targetRequestId,
                            action: 'accept',
                          );
                      if (res['success'] == true) {
                        _optimisticallyUpdateNightPartnerRequest(
                          targetRequestId,
                          'accepted',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Invite accepted! Waiting for booking confirmation. 🎉',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _loadFeed(showLoader: false, forceRefresh: true);
                      } else {
                        final errMsg =
                            res['message']?.toString() ??
                            'Could not accept invite. Match slot may already be filled.';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errMsg),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        _loadFeed(showLoader: false, forceRefresh: true);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _activeActionKeys.remove(acceptKey));
                      }
                    }
                  },
          ),
        );

        actionsList.add(
          NotificationAction(
            label: isDeclining ? 'Declining...' : 'Decline',
            icon: Icons.close_rounded,
            isPrimary: false,
            isLoading: isDeclining,
            color: Colors.white54,
            onTap: (isAccepting || isDeclining)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(declineKey));
                    try {
                      final res =
                          await ApiService.respondToNightPartnerRequestDetailed(
                            requestId: targetRequestId,
                            action: 'decline',
                          );
                      if (res['success'] == true) {
                        _optimisticallyUpdateNightPartnerRequest(
                          targetRequestId,
                          'rejected',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invite declined.'),
                            backgroundColor: Colors.grey,
                          ),
                        );
                        _loadFeed(showLoader: false, forceRefresh: true);
                      } else {
                        final errMsg =
                            res['message']?.toString() ??
                            'Could not decline invite.';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errMsg),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        _loadFeed(showLoader: false, forceRefresh: true);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _activeActionKeys.remove(declineKey));
                      }
                    }
                  },
          ),
        );
      } else {
        accentColor = const Color(0xFF8B5CF6);
        badgeText = 'INVITE SENT';
        cardTitle = 'Invite Sent ⏳';

        final List<String> invitedNames = [];
        for (final e in entries) {
          final p = e['partner'] ?? e['data']?['partner'] ?? e['metadata']?['partner'];
          final name = p is Map ? (p['firstName'] ?? p['name']) : (e['otherUserName'] ?? e['senderName']);
          if (name != null && name.toString().trim().isNotEmpty) {
            final clean = name.toString().trim();
            if (!invitedNames.contains(clean)) invitedNames.add(clean);
          }
        }
        if (invitedNames.length > 1) {
          cardBody =
              'Invited ${invitedNames[0]} + ${invitedNames.length - 1} others to join $displayTitle. Waiting for response.';
        } else {
          cardBody =
              'Invited $partnerName to join $displayTitle. Waiting for response.';
        }

        actionsList.add(
          NotificationAction(
            label: 'Cancel Invite',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.red[400],
            onTap: () async {
              for (final e in entries) {
                final reqId = e['requestId'] ??
                    e['data']?['requestId'] ??
                    e['metadata']?['requestId'] ??
                    (e['id']?.toString().startsWith('upcoming_night_timeline_') == false ? e['id'] : null);
                if (reqId != null) {
                  await ApiService.cancelUpcomingNight(
                    targetId: reqId.toString(),
                    reason: 'Host cancelled invite',
                  );
                }
              }
              if (targetRequestId.isNotEmpty) {
                await ApiService.cancelUpcomingNight(
                  targetId: targetRequestId,
                  reason: 'Host cancelled invite',
                );
              }
              _loadFeed(showLoader: false, forceRefresh: true);
            },
          ),
        );
      }
    }

    return UnifiedNotificationItem(
      id: 'upcoming_night_timeline_$nightId',
      category: 'upcoming_night',
      title: cardTitle,
      body: cardBody,
      createdAt: latestTime,
      timeAgo: _formatTimeAgo(latestTime.toIso8601String()),
      isRead: (badgeText == 'ACTION REQUIRED' || badgeText == 'INVITE')
          ? false
          : true,
      isExpired: false,
      badgeText: badgeText,
      accentColor: accentColor,
      categoryIcon: Icons.nightlife_rounded,
      avatarUrl: partnerPhoto ?? venuePhoto,
      actions: actionsList.isNotEmpty ? actionsList : null,
      rawData: {
        ...rawItem,
        ...metadata,
        'nightId': nightId,
        'matchId': matchId,
        'venueName': venueName,
        'partnerName': partnerName,
        'partnerPhoto': partnerPhoto,
        'ticketId': ticketId,
        'chatId': chatId,
      },
      statusSummary: status,
    );
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
        if (e['venue'] != null ||
            e['creator'] != null ||
            e['planDateTime'] != null) {
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
    final venueName =
        venue['name']?.toString() ??
        planMap['venueName']?.toString() ??
        'Party Venue';

    Map<String, dynamic> hostCreator =
        (planMap['creator'] is Map && (planMap['creator'] as Map).isNotEmpty)
        ? Map<String, dynamic>.from(planMap['creator'])
        : (planMap['host'] is Map && (planMap['host'] as Map).isNotEmpty
              ? Map<String, dynamic>.from(planMap['host'])
              : (planMap['user'] is Map && (planMap['user'] as Map).isNotEmpty
                    ? Map<String, dynamic>.from(planMap['user'])
                    : <String, dynamic>{}));

    if (hostCreator.isEmpty) {
      for (final e in entries) {
        if (e['creator'] is Map && (e['creator'] as Map).isNotEmpty) {
          hostCreator = Map<String, dynamic>.from(e['creator']);
          break;
        }
        if (e['host'] is Map && (e['host'] as Map).isNotEmpty) {
          hostCreator = Map<String, dynamic>.from(e['host']);
          break;
        }
        if (e['user'] is Map && (e['user'] as Map).isNotEmpty) {
          hostCreator = Map<String, dynamic>.from(e['user']);
          break;
        }
        if (e['data'] is Map) {
          final d = e['data'] as Map;
          if (d['creator'] is Map) {
            hostCreator = Map<String, dynamic>.from(d['creator']);
            break;
          }
          if (d['host'] is Map) {
            hostCreator = Map<String, dynamic>.from(d['host']);
            break;
          }
          if (d['user'] is Map) {
            hostCreator = Map<String, dynamic>.from(d['user']);
            break;
          }
        }
      }
    }

    String hostName = '';
    if (hostCreator['firstName'] != null || hostCreator['name'] != null) {
      final fn = hostCreator['firstName'] ?? hostCreator['name'];
      final ln = hostCreator['lastName'] ?? '';
      hostName = '$fn $ln'.trim();
    } else if (planMap['hostName'] != null &&
        planMap['hostName'].toString().trim().isNotEmpty) {
      hostName = planMap['hostName'].toString().trim();
    } else if (planMap['userName'] != null &&
        planMap['userName'].toString().trim().isNotEmpty) {
      hostName = planMap['userName'].toString().trim();
    } else if (planMap['hostFirstName'] != null) {
      hostName = '${planMap['hostFirstName']} ${planMap['hostLastName'] ?? ''}'
          .trim();
    } else {
      hostName = 'Party Host';
    }

    String? rawHostPhoto =
        _extractUserPhoto(hostCreator) ??
        _extractUserPhoto(planMap['creator']) ??
        _extractUserPhoto(planMap['host']) ??
        _extractUserPhoto(planMap['user']) ??
        _extractUserPhoto(planMap['sender']) ??
        _extractUserPhoto(planMap['actor']) ??
        _extractUserPhoto(planMap);

    if (rawHostPhoto == null || rawHostPhoto.isEmpty) {
      for (final e in entries) {
        rawHostPhoto =
            _extractUserPhoto(e['creator']) ??
            _extractUserPhoto(e['host']) ??
            _extractUserPhoto(e['user']) ??
            _extractUserPhoto(e['sender']) ??
            _extractUserPhoto(e['actor']) ??
            _extractUserPhoto(
              e['data'] is Map ? _extractUserPhoto(e['data']['creator']) : null,
            ) ??
            _extractUserPhoto(
              e['data'] is Map ? _extractUserPhoto(e['data']['host']) : null,
            ) ??
            _extractUserPhoto(
              e['data'] is Map ? _extractUserPhoto(e['data']['user']) : null,
            ) ??
            _extractUserPhoto(
              e['data'] is Map ? _extractUserPhoto(e['data']['sender']) : null,
            ) ??
            _extractUserPhoto(e['data']) ??
            _extractUserPhoto(e);
        if (rawHostPhoto != null && rawHostPhoto.isNotEmpty) break;
      }
    }

    String? hostPhoto = rawHostPhoto != null
        ? ApiService.formatImageUrl(rawHostPhoto)
        : null;

    // Robustly extract planHostId from all possible locations
    String planHostId =
        (planMap['userId'] ??
                planMap['hostId'] ??
                planMap['creatorId'] ??
                hostCreator['id'] ??
                planMap['payActionPayload']?['hostId'] ??
                planMap['payActionPayload']?['userId'] ??
                '')
            .toString();

    if (planHostId.isEmpty) {
      for (final e in entries) {
        final hid =
            (e['hostId'] ??
                    e['userId'] ??
                    e['creatorId'] ??
                    e['metadata']?['hostId'] ??
                    e['metadata']?['userId'] ??
                    e['data']?['hostId'] ??
                    e['data']?['userId'] ??
                    e['payActionPayload']?['hostId'] ??
                    e['payActionPayload']?['userId'] ??
                    '')
                .toString();
        if (hid.isNotEmpty) {
          planHostId = hid;
          break;
        }
      }
    }

    final bool isHostExplicit = entries.any(
      (e) =>
          e['role'] == 'host' ||
          e['payActionPayload']?['isHost'] == true ||
          e['requestType'] == 'party_plan_host_deposit' ||
          e['category'] == 'party_plan_host_deposit' ||
          e['id']?.toString().startsWith('pending_pp_') == true ||
          e['id']?.toString().startsWith('pp_host_deposit_') == true ||
          (e['hostRazorpayOrderId'] != null &&
              e['hostRazorpayOrderId'].toString().isNotEmpty &&
              e['hostPaymentStatus'] != 'paid'),
    );

    final bool isHost =
        isHostExplicit ||
        (currentUserId.isNotEmpty &&
            (planHostId == currentUserId || planMap['role'] == 'host'));

    if (isHost && (hostCreator.isEmpty || hostName == 'Party Host')) {
      final cu = ApiService.cachedCurrentUser;
      if (cu != null) {
        final cuName = '${cu.firstName} ${cu.lastName}'.trim();
        final cuPhoto =
            cu.profilePhoto ?? (cu.photos.isNotEmpty ? cu.photos.first : null);
        hostCreator = {
          'id': currentUserId,
          'firstName': cu.firstName,
          'lastName': cu.lastName,
          'profilePhotoUrl': cuPhoto,
          'profileImageUrl': cuPhoto,
        };
        hostName = cuName.isNotEmpty ? cuName : 'You';
        if (hostPhoto == null || hostPhoto.isEmpty) {
          hostPhoto = cuPhoto;
        }
      }
    }

    final Map<String, dynamic> hostUserObj = {
      'id': planHostId.isNotEmpty ? planHostId : (hostCreator['id'] ?? ''),
      'name': hostName,
      'firstName': hostName,
      'lastName': hostCreator['lastName'] ?? '',
      'profilePhotoUrl': hostPhoto,
      'profileImageUrl': hostPhoto,
      'photoUrl': hostPhoto,
      'profilePhoto': hostPhoto,
    };
    if (hostCreator.isNotEmpty) {
      hostUserObj.addAll(hostCreator);
      if (hostPhoto != null) {
        hostUserObj['profilePhotoUrl'] = hostPhoto;
        hostUserObj['profileImageUrl'] = hostPhoto;
        hostUserObj['photoUrl'] = hostPhoto;
        hostUserObj['profilePhoto'] = hostPhoto;
      }
    }
    if (hostPhoto != null) {
      hostUserObj['photos'] = [
        {'url': hostPhoto, 'filePath': hostPhoto, 'isPrimary': true},
      ];
    }

    final List<String> selectedUserIdsList = [];
    final rawSel = planMap['selectedUsers'] ?? planMap['selectedUserIds'];
    if (rawSel is List) {
      for (final u in rawSel) {
        if (u != null && u.toString().trim().isNotEmpty) {
          selectedUserIdsList.add(u.toString().trim());
        }
      }
    }
    for (final e in entries) {
      final sUsers =
          e['selectedUsers'] ??
          e['selectedUserIds'] ??
          e['data']?['selectedUsers'] ??
          e['metadata']?['selectedUsers'];
      if (sUsers is List) {
        for (final u in sUsers) {
          if (u != null &&
              u.toString().trim().isNotEmpty &&
              !selectedUserIdsList.contains(u.toString().trim())) {
            selectedUserIdsList.add(u.toString().trim());
          }
        }
      }
    }

    // 3. Find requests involving current user or host
    Map<String, dynamic>? myRequest;
    final List<Map<String, dynamic>> pendingIncomingRequests = [];
    final List<Map<String, dynamic>> pendingOutboundInvites = [];
    Map<String, dynamic>? acceptedJoinerRequest;

    for (final e in entries) {
      final reqType = (e['type'] ?? e['requestType'] ?? '').toString();
      final status = (e['status'] ?? '').toString().toLowerCase();
      final String requesterId =
          (e['requesterId'] ??
                  e['requester']?['id'] ??
                  e['userId'] ??
                  e['actorUserId'] ??
                  '')
              .toString();
      final String recipientId =
          (e['recipientId'] ??
                  e['targetUserId'] ??
                  e['metadata']?['recipientId'] ??
                  e['metadata']?['targetUserId'] ??
                  '')
              .toString();

      final bool isInvite =
          e['isInvite'] == true ||
          e['requestType'] == 'private_invite' ||
          e['type'] == 'party_plan_invitation' ||
          e['requestType'] == 'party_plan_invitation' ||
          e['eventType'] == 'party_plan_invitation' ||
          e['type'] == 'party_plan_invite_sent' ||
          e['requestType'] == 'party_plan_invite_sent' ||
          (selectedUserIdsList.isNotEmpty &&
              (selectedUserIdsList.contains(requesterId) ||
                  selectedUserIdsList.contains(recipientId)));

      if (reqType == 'my_request' ||
          requesterId == currentUserId ||
          (isInvite && recipientId == currentUserId)) {
        myRequest = e;
      }
      if (isHost) {
        if (isInvite) {
          if (status == 'pending') {
            pendingOutboundInvites.add(e);
          } else if (status == 'accepted' ||
              status == 'payment_pending' ||
              status == 'paid' ||
              status == 'confirmed') {
            acceptedJoinerRequest = e;
          }
        } else {
          if (status == 'pending') {
            pendingIncomingRequests.add(e);
          } else if (status == 'accepted' ||
              status == 'payment_pending' ||
              status == 'paid' ||
              status == 'confirmed') {
            acceptedJoinerRequest = e;
          }
        }
      } else {
        if (reqType == 'incoming_request' ||
            (isInvite && recipientId == currentUserId)) {
          if (status == 'pending') {
            pendingIncomingRequests.add(e);
          } else if (status == 'accepted' ||
              status == 'payment_pending' ||
              status == 'paid' ||
              status == 'confirmed') {
            acceptedJoinerRequest = e;
          }
        }
      }
      if (isHost && (status == 'confirmed' || status == 'paid')) {
        acceptedJoinerRequest = e;
      }
    }

    // 4. Format plan date & time
    String formattedDateTime = '';
    final rawDateTime =
        planMap['planDateTime'] ??
        planMap['eventDateTime'] ??
        planMap['planDate'];
    final rawStartTime = planMap['startTime'] ?? planMap['time'];
    final parsedEventDate = _parseEventDateTime(rawDateTime, rawStartTime);
    if (parsedEventDate != null) {
      try {
        const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const monthNames = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final w = weekdayNames[parsedEventDate.weekday - 1];
        final m = monthNames[parsedEventDate.month - 1];
        final hour = parsedEventDate.hour % 12 == 0
            ? 12
            : parsedEventDate.hour % 12;
        final ampm = parsedEventDate.hour >= 12 ? 'PM' : 'AM';
        final minute = parsedEventDate.minute.toString().padLeft(2, '0');
        formattedDateTime =
            '$w, ${parsedEventDate.day} $m • $hour:$minute $ampm';
      } catch (_) {}
    }

    // 5. Expiration & Status Checks
    bool isExpired = false;
    if (parsedEventDate != null &&
        DateTime.now().isAfter(parsedEventDate.add(const Duration(hours: 4)))) {
      isExpired = true;
    }

    final String planStatus = (planMap['status'] ?? '')
        .toString()
        .toLowerCase();
    final String lifecycleStatus = (planMap['lifecycleStatus'] ?? '')
        .toString()
        .toLowerCase();
    bool anyHostPaid = false;
    for (final e in entries) {
      final hps = (e['hostPaymentStatus'] ??
              e['plan']?['hostPaymentStatus'] ??
              e['paymentStatus'] ??
              '')
          .toString()
          .toLowerCase();
      if (hps == 'paid' ||
          hps == 'completed' ||
          e['isLive'] == true ||
          e['plan']?['isLive'] == true) {
        anyHostPaid = true;
        break;
      }
    }
    final String hostPaymentStatus = anyHostPaid
        ? 'paid'
        : (planMap['hostPaymentStatus'] ?? '').toString().toLowerCase();

    if (planStatus == 'expired' ||
        lifecycleStatus == 'expired' ||
        lifecycleStatus == 'payment_expired') {
      isExpired = true;
    }

    final bool isCancelled =
        planStatus == 'cancelled' || lifecycleStatus == 'cancelled';

    final String hostReachStatus =
        (planMap['hostReachStatus'] ??
                (planMap['hostArrivalConfirmed'] == true
                    ? 'REACHED'
                    : 'PENDING'))
            .toString()
            .toUpperCase();
    final String partnerReachStatus =
        (acceptedJoinerRequest?['partnerReachStatus'] ??
                myRequest?['partnerReachStatus'] ??
                planMap['partnerReachStatus'] ??
                ((acceptedJoinerRequest?['guestArrivalConfirmed'] == true ||
                        myRequest?['guestArrivalConfirmed'] == true)
                    ? 'REACHED'
                    : 'PENDING'))
            .toString()
            .toUpperCase();

    final bool hostIsReached =
        hostReachStatus == 'REACHED' || planMap['hostArrivalConfirmed'] == true;
    final bool hostIsNotReached = hostReachStatus == 'NOT_REACHED';
    final bool partnerIsReached =
        partnerReachStatus == 'REACHED' ||
        acceptedJoinerRequest?['guestArrivalConfirmed'] == true ||
        myRequest?['guestArrivalConfirmed'] == true;
    final bool partnerIsNotReached = partnerReachStatus == 'NOT_REACHED';

    final bool bothReached = hostIsReached && partnerIsReached;
    final String myReachStatus = isHost ? hostReachStatus : partnerReachStatus;
    final bool myHasResponded =
        myReachStatus == 'REACHED' || myReachStatus == 'NOT_REACHED';
    final String otherReachStatus = isHost
        ? partnerReachStatus
        : hostReachStatus;

    final bool isRefunded =
        hostPaymentStatus == 'refunded' ||
        (myRequest != null && myRequest['joinerPaymentStatus'] == 'refunded') ||
        lifecycleStatus == 'plan_completed' ||
        planStatus == 'completed' ||
        planMap['paymentStatus']?.toString().toLowerCase().contains(
              'refunded',
            ) ==
            true;

    final bool reach30mSent = planMap['reachConfirmation30mSent'] == true;
    final bool inArrivalWindow =
        reach30mSent ||
        (parsedEventDate != null &&
            parsedEventDate.difference(DateTime.now()).inMinutes <= 35 &&
            parsedEventDate.difference(DateTime.now()).inHours >= -24);

    // A plan-level lifecycleStatus/acceptedJoinerRequest only genuinely reflects
    // the current viewer's own match when they're the host (there's only one
    // host per plan, so the plan's own state IS their state). A non-host viewer
    // must only trust their own myRequest — otherwise a rejected/pending/
    // uninvolved user viewing a plan that got matched with someone else would
    // incorrectly see "Match Confirmed" with working Chat/Ticket buttons.
    final bool isConfirmed =
        (isHost &&
            (lifecycleStatus == 'match_confirmed' ||
                lifecycleStatus == 'chat_enabled' ||
                lifecycleStatus == 'plan_completed' ||
                (acceptedJoinerRequest != null &&
                    (acceptedJoinerRequest['status'] == 'confirmed' ||
                        acceptedJoinerRequest['status'] == 'paid' ||
                        acceptedJoinerRequest['joinerPaymentStatus'] ==
                            'paid')))) ||
        (myRequest != null &&
            (myRequest['status'] == 'confirmed' ||
                myRequest['status'] == 'paid' ||
                myRequest['joinerPaymentStatus'] == 'paid'));

    String countdownLabel = '30m';
    String timeRemainingText = '';
    bool isPaymentExpired = false;
    final rawDeadline =
        myRequest?['paymentDeadlineAt'] ??
        myRequest?['paymentTimeoutAt'] ??
        planMap['paymentDeadlineAt'] ??
        planMap['paymentTimeoutAt'];

    if (rawDeadline != null) {
      try {
        final deadline = DateTime.parse(rawDeadline.toString()).toLocal();
        final remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative) {
          isPaymentExpired = true;
          countdownLabel = 'Expired';
          timeRemainingText = 'Expired';
        } else {
          final m = remaining.inMinutes;
          final s = remaining.inSeconds % 60;
          countdownLabel = '${m}m ${s.toString().padLeft(2, "0")}s';
          timeRemainingText =
              '${m}m ${s.toString().padLeft(2, "0")}s remaining';
        }
      } catch (_) {}
    }

    if (isPaymentExpired && !isConfirmed) {
      isExpired = true;
    }

    // 6. Contextual Title, Role, Partner & Actions
    Color accent = const Color(0xFF8B5CF6);
    String title = 'Let\'s party at $venueName! 🚀';
    String body = formattedDateTime.isNotEmpty
        ? '📅 $formattedDateTime'
        : 'Party Plan at $venueName';
    String badge = 'PARTY PLAN';
    List<NotificationAction>? actionsList;
    Map<String, dynamic>? senderUser = hostUserObj;
    String? avatarUrl = hostPhoto;

    String? userRoleLabel = isHost ? '👑 Your Party Plan' : 'Hosted by';
    Map<String, dynamic>? partnerUser = isHost ? null : hostUserObj;
    String? partnerRoleLabel = isHost ? null : 'Host:';
    String? statusSummary;

    if (isHost && acceptedJoinerRequest != null) {
      final joinerReq =
          (acceptedJoinerRequest['requester'] is Map &&
              (acceptedJoinerRequest['requester'] as Map).isNotEmpty)
          ? Map<String, dynamic>.from(acceptedJoinerRequest['requester'])
          : (acceptedJoinerRequest['user'] is Map &&
                    (acceptedJoinerRequest['user'] as Map).isNotEmpty
                ? Map<String, dynamic>.from(acceptedJoinerRequest['user'])
                : <String, dynamic>{
                    'id': acceptedJoinerRequest['requesterId'],
                    'name': acceptedJoinerRequest['requesterName'] ?? 'Joiner',
                    'firstName':
                        acceptedJoinerRequest['requesterName'] ?? 'Joiner',
                    'profilePhotoUrl':
                        acceptedJoinerRequest['requesterPhotoUrl'],
                    'profileImageUrl':
                        acceptedJoinerRequest['requesterPhotoUrl'],
                  });
      partnerUser = joinerReq;
      partnerRoleLabel = 'Guest:';
    }

    Map<String, dynamic>? pendingCancellationEntry;
    for (final e in entries) {
      final eType = (e['type'] ?? e['eventType'] ?? '').toString();
      final cat = (e['category'] ?? '').toString();
      if (eType == 'party_plan_cancellation_requested' ||
          cat == 'party_plan_cancellation_requested') {
        pendingCancellationEntry = e;
        break;
      }
    }

    final bool isCancellationRequested =
        (lifecycleStatus == 'cancellation_requested' ||
            pendingCancellationEntry != null) &&
        !isCancelled;

    if (isExpired) {
      accent = const Color(0xFF9CA3AF);
      badge = 'EXPIRED';
      title = 'Party Plan Expired ⌛';
      body = 'This Party Plan at $venueName has expired.';
      actionsList = null;
      statusSummary = 'Plan Expired';
    } else if (isCancelled) {
      accent = const Color(0xFFEF4444);
      badge = 'CANCELLED';
      title = '❌ Party Plan Cancelled';
      body =
          'Party Plan at $venueName was cancelled. ₹99 Commitment Deposit has been credited to your Lunara Wallet.';
      statusSummary = 'Cancelled • Deposit Credited';
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
            MaterialPageRoute(
              builder: (_) => PartyPlanDetailScreen(plan: planMap),
            ),
          ).then((_) => _loadFeed(showLoader: false)),
        ),
      ];
    } else if (isCancellationRequested) {
      final String requestedById =
          (pendingCancellationEntry?['requestedById'] ??
                  pendingCancellationEntry?['metadata']?['requestedById'] ??
                  pendingCancellationEntry?['actorUserId'] ??
                  planMap['cancellationRequest']?['requestedById'] ??
                  planMap['requestedById'] ??
                  '')
              .toString();
      final String recipientUserId =
          (pendingCancellationEntry?['recipientUserId'] ??
                  pendingCancellationEntry?['metadata']?['recipientUserId'] ??
                  planMap['cancellationRequest']?['recipientUserId'] ??
                  '')
              .toString();
      final bool isRecipient = requestedById.isNotEmpty
          ? (requestedById != currentUserId)
          : (recipientUserId.isNotEmpty && recipientUserId == currentUserId);
      final String requesterName = (requestedById.isNotEmpty && requestedById != currentUserId)
          ? (isHost
              ? (partnerUser?['firstName'] ??
                    partnerUser?['name'] ??
                    'Your partner')
              : (hostUserObj['firstName'] ?? hostUserObj['name'] ?? 'Host'))
          : 'You';
      final String reasonKey =
          (pendingCancellationEntry?['reason'] ??
                  pendingCancellationEntry?['metadata']?['reason'] ??
                  planMap['cancellationRequest']?['reason'] ??
                  'my_plans_changed')
              .toString();
      final Map<String, String> reasonLabels = {
        'my_plans_changed': 'My plans have changed',
        'not_available': 'I\'m not available anymore',
        'not_interested': 'Not interested anymore',
        'found_another_plan': 'Found another plan',
        'venue_changed': 'Venue changed',
        'personal_reasons': 'Personal reasons',
        'other': 'Other reasons',
      };
      final reasonText = reasonLabels[reasonKey] ?? reasonKey;
      final String cancelReqId =
          (pendingCancellationEntry?['requestId'] ??
                  pendingCancellationEntry?['id'] ??
                  pendingCancellationEntry?['metadata']?['requestId'] ??
                  planMap['cancellationRequest']?['id'] ??
                  planMap['cancellationRequestId'] ??
                  '')
              .toString();

      accent = const Color(0xFFF59E0B);
      badge = isRecipient ? 'ACTION REQUIRED' : 'CANCELLATION PENDING';

      if (isRecipient) {
        title = '⚠️ Cancellation Requested';
        body =
            '$requesterName has requested to cancel this Party Plan at $venueName.\nReason: "$reasonText"';
        statusSummary = 'Approval Required';
        final acceptCancelKey = 'accept_cancel_pp_$planId';
        final keepPlanKey = 'keep_plan_pp_$planId';
        final isAcceptingCancel = _activeActionKeys.contains(acceptCancelKey);
        final isKeepingPlan = _activeActionKeys.contains(keepPlanKey);

        actionsList = [
          NotificationAction(
            label: isAcceptingCancel ? 'Accepting...' : 'Accept Cancellation',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            isLoading: isAcceptingCancel,
            color: Colors.redAccent,
            onTap: (isAcceptingCancel || isKeepingPlan)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(acceptCancelKey));
                    try {
                      final res =
                          await ApiService.respondToPartyPlanCancellationRequest(
                            planId: planId,
                            requestId: cancelReqId,
                            action: 'approve',
                          );
                      if (res['success'] == true) {
                        _optimisticallyUpdatePartyPlanRequest(
                          planId,
                          'cancelled',
                        );
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              res['message'] ??
                                  (res['success'] == true
                                      ? 'Party Plan cancelled. Commitment deposit credited to wallet!'
                                      : 'Failed to cancel Party Plan.'),
                            ),
                            backgroundColor: res['success'] == true
                                ? Colors.green
                                : Colors.red,
                          ),
                        );
                        _loadFeed(showLoader: false, forceRefresh: true);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(
                          () => _activeActionKeys.remove(acceptCancelKey),
                        );
                      }
                    }
                  },
          ),
          NotificationAction(
            label: isKeepingPlan ? 'Keeping...' : 'Keep Plan',
            icon: Icons.shield_rounded,
            isPrimary: false,
            isLoading: isKeepingPlan,
            color: Colors.grey[200],
            onTap: (isAcceptingCancel || isKeepingPlan)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(keepPlanKey));
                    try {
                      final res =
                          await ApiService.respondToPartyPlanCancellationRequest(
                            planId: planId,
                            requestId: cancelReqId,
                            action: 'reject',
                          );
                      if (res['success'] == true) {
                        _optimisticallyUpdatePartyPlanRequest(planId, 'active');
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              res['message'] ??
                                  (res['success'] == true
                                      ? 'Cancellation declined. Party Plan remains active.'
                                      : 'Failed to decline cancellation.'),
                            ),
                            backgroundColor: res['success'] == true
                                ? Colors.grey.shade800
                                : Colors.red,
                          ),
                        );
                        _loadFeed(showLoader: false, forceRefresh: true);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _activeActionKeys.remove(keepPlanKey));
                      }
                    }
                  },
          ),
        ];
      } else {
        title = '⏳ Cancellation Request Sent';
        body =
            'You requested to cancel this Party Plan at $venueName. Waiting for the other participant to approve.';
        statusSummary = 'Waiting for Approval';
        actionsList = [
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      }
    } else if (bothReached || isRefunded) {
      final otherId = isHost
          ? (acceptedJoinerRequest?['requesterId'] ??
                acceptedJoinerRequest?['requester']?['id'] ??
                partnerUser?['id'] ??
                '')
          : (planHostId.isNotEmpty ? planHostId : (hostCreator['id'] ?? ''));
      final String partnerDisplayName =
          (isHost
                  ? (partnerUser?['firstName'] ??
                        partnerUser?['name'] ??
                        'Partner')
                  : (hostCreator['firstName'] ?? hostName))
              .trim();
      final String? otherPhoto = isHost
          ? (partnerUser?['profileImageUrl'] ??
                partnerUser?['profilePhotoUrl'] ??
                acceptedJoinerRequest?['requesterPhotoUrl'])
          : hostPhoto;

      title = '🎉 Party Plan Confirmed';
      badge = 'COMPLETED';
      accent = const Color(0xFF10B981);
      body =
          '✓ Both reached the venue • 💰 ₹99 Deposit refunded to LUNARA Wallet.';
      statusSummary = '✓ Both Reached • ₹99 Refunded';
      actionsList = [
        NotificationAction(
          label: 'View Ticket',
          icon: Icons.confirmation_number_rounded,
          isPrimary: true,
          onTap: () {
            // Enrich planMap with already-resolved host data so the ticket
            // screen can render the host profile instantly (no async wait).
            final enrichedPlan = Map<String, dynamic>.from(planMap);
            if (enrichedPlan['host'] == null && hostUserObj.isNotEmpty) {
              enrichedPlan['host'] = Map<String, dynamic>.from(hostUserObj);
            }
            if (enrichedPlan['creator'] == null && hostCreator.isNotEmpty) {
              enrichedPlan['creator'] = Map<String, dynamic>.from(hostCreator);
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanTicketScreen(
                  request: acceptedJoinerRequest ?? myRequest ?? enrichedPlan,
                  plan: enrichedPlan,
                  isHost: isHost,
                ),
              ),
            );
          },
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
                  'id': otherId,
                  'firstName': partnerDisplayName,
                  'profilePhotoUrl': otherPhoto,
                },
              ),
            ),
          ),
        ),
        NotificationAction(
          label: 'View Wallet',
          icon: Icons.account_balance_wallet_rounded,
          isPrimary: false,
          color: Colors.grey[200],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
          ),
        ),
      ];
    } else if (isConfirmed && inArrivalWindow) {
      final otherId = isHost
          ? (acceptedJoinerRequest?['requesterId'] ??
                acceptedJoinerRequest?['requester']?['id'] ??
                partnerUser?['id'] ??
                '')
          : (planHostId.isNotEmpty ? planHostId : (hostCreator['id'] ?? ''));
      final String partnerDisplayName =
          (isHost
                  ? (partnerUser?['firstName'] ??
                        partnerUser?['name'] ??
                        'Partner')
                  : (hostCreator['firstName'] ?? hostName))
              .trim();
      final String? otherPhoto = isHost
          ? (partnerUser?['profileImageUrl'] ??
                partnerUser?['profilePhotoUrl'] ??
                acceptedJoinerRequest?['requesterPhotoUrl'])
          : hostPhoto;

      final String hostStatusText = hostIsReached
          ? '🟢 Reached'
          : (hostIsNotReached ? '❌ Not reached' : '⚪ Waiting for response');
      final String partnerStatusText = partnerIsReached
          ? '🟢 Reached'
          : (partnerIsNotReached ? '❌ Not reached' : '⚪ Waiting for response');

      title = myHasResponded
          ? (myReachStatus == 'REACHED'
                ? '📍 Arrival Confirmed'
                : '📍 Venue Status Updated')
          : '📍 Have you reached the venue?';
      badge = myHasResponded ? 'CONFIRMED' : 'ACTION REQUIRED';
      accent = myHasResponded
          ? const Color(0xFF6366F1)
          : const Color(0xFFF59E0B);

      body =
          '📍 $venueName${formattedDateTime.isNotEmpty ? ' • $formattedDateTime' : ''}\n'
          'Host (${isHost ? "You" : hostName}): $hostStatusText\n'
          'Partner (${!isHost ? "You" : partnerDisplayName}): $partnerStatusText';

      if (bothReached) {
        statusSummary = '✓ Both Reached';
      } else if (myReachStatus == 'REACHED') {
        statusSummary = 'Waiting for Partner';
      } else if (myReachStatus == 'NOT_REACHED') {
        statusSummary = 'You: Not Reached';
      } else {
        statusSummary = 'Confirm Arrival';
      }

      actionsList = [];

      // If user hasn't responded yet, render YES and NO confirmation buttons directly on the card
      if (!myHasResponded) {
        final reachYesKey = 'reach_yes_$planId';
        final reachNoKey = 'reach_no_$planId';
        final isReachYes = _activeActionKeys.contains(reachYesKey);
        final isReachNo = _activeActionKeys.contains(reachNoKey);

        actionsList.add(
          NotificationAction(
            label: isReachYes ? 'Confirming...' : 'YES, REACHED',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            isLoading: isReachYes,
            color: const Color(0xFF10B981),
            onTap: (isReachYes || isReachNo)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(reachYesKey));
                    try {
                      final res = await ApiService.confirmArrival(
                        planId: planId,
                        userId: currentUserId,
                        hasArrived: true,
                        stage: 'thirty_min_reach',
                        source: 'LIVE_FEED_CARD',
                      );
                      if (context.mounted) {
                        if (res['bothArrived'] == true) {
                          PartyPlanArrivalDialog.showBothArrivedSuccessDialog(
                            context,
                            venueName: venueName,
                            plan: planMap,
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                res['message'] ??
                                    'Arrival confirmed! ₹99 refund will be credited once both arrive.',
                              ),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        }
                        _loadFeed(showLoader: false);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to confirm arrival: $e'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _activeActionKeys.remove(reachYesKey));
                      }
                    }
                  },
          ),
        );

        actionsList.add(
          NotificationAction(
            label: isReachNo ? 'Updating...' : 'NO, NOT REACHED',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            isLoading: isReachNo,
            color: Colors.grey[200],
            onTap: (isReachYes || isReachNo)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(reachNoKey));
                    try {
                      final res = await ApiService.confirmArrival(
                        planId: planId,
                        userId: currentUserId,
                        hasArrived: false,
                        stage: 'thirty_min_reach',
                        source: 'LIVE_FEED_CARD',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              res['message'] ??
                                  'Status updated: Not reached venue yet.',
                            ),
                            backgroundColor: Colors.grey.shade800,
                          ),
                        );
                        _loadFeed(showLoader: false);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to update status: $e'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _activeActionKeys.remove(reachNoKey));
                      }
                    }
                  },
          ),
        );
      }

      // Always show View Ticket & Chat
      actionsList.add(
        NotificationAction(
          label: 'View Ticket',
          icon: Icons.confirmation_number_rounded,
          isPrimary: myHasResponded,
          color: myHasResponded ? const Color(0xFF6366F1) : Colors.grey[200],
          onTap: () {
            // Enrich planMap with already-resolved host data so the ticket
            // screen can render the host profile instantly (no async wait).
            final enrichedPlan = Map<String, dynamic>.from(planMap);
            if (enrichedPlan['host'] == null && hostUserObj.isNotEmpty) {
              enrichedPlan['host'] = Map<String, dynamic>.from(hostUserObj);
            }
            if (enrichedPlan['creator'] == null && hostCreator.isNotEmpty) {
              enrichedPlan['creator'] = Map<String, dynamic>.from(hostCreator);
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanTicketScreen(
                  request: acceptedJoinerRequest ?? myRequest ?? enrichedPlan,
                  plan: enrichedPlan,
                  isHost: isHost,
                ),
              ),
            );
          },
        ),
      );

      actionsList.add(
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
                  'id': otherId,
                  'firstName': partnerDisplayName,
                  'profilePhotoUrl': otherPhoto,
                },
              ),
            ),
          ),
        ),
      );

      if (myHasResponded) {
        actionsList.add(
          NotificationAction(
            label: 'Cancel Plan',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.red[50],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        );
      }
    } else if (isHost) {
      userRoleLabel = '👑 Your Party Plan';
      final planVis = planMap['visibility']?.toString().toUpperCase() ?? '';
      final bool isPrivatePlan = planVis == 'PRIVATE';
      final bool isBothPlan = planVis == 'BOTH';

      if (hostPaymentStatus != 'paid' && hostPaymentStatus != 'completed') {
        dynamic rawDeposit = planMap['depositAmount'];
        if (rawDeposit == null) {
          for (final e in entries) {
            if (e['depositAmount'] != null) {
              rawDeposit = e['depositAmount'];
              break;
            }
            if (e['amountDue'] != null) {
              rawDeposit = e['amountDue'];
              break;
            }
          }
        }
        final double depositAmt = rawDeposit is num
            ? rawDeposit.toDouble()
            : (double.tryParse(rawDeposit?.toString() ?? '') ?? 99.0);
        String hostOrderId = planMap['hostRazorpayOrderId']?.toString() ?? '';
        if (hostOrderId.isEmpty) {
          for (final e in entries) {
            final oid =
                (e['hostRazorpayOrderId'] ??
                        e['payActionPayload']?['orderId'] ??
                        e['metadata']?['hostRazorpayOrderId'] ??
                        e['data']?['hostRazorpayOrderId'])
                    ?.toString();
            if (oid != null && oid.isNotEmpty) {
              hostOrderId = oid;
              break;
            }
          }
        }
        title = '⚡ Action Required: Pay Host Deposit';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFF8B5CF6);
        body =
            'Pay deposit of ₹${depositAmt.toStringAsFixed(0)} to publish your Party Plan at $venueName!';
        final isPayingHost = _activeActionKeys.contains('pay_host_pp_$planId');
        actionsList = [
          NotificationAction(
            label: isPayingHost
                ? 'Opening Gateway...'
                : 'Pay Deposit (₹${depositAmt.toStringAsFixed(0)})',
            icon: Icons.payment_rounded,
            isPrimary: true,
            isLoading: isPayingHost,
            onTap: isPayingHost
                ? () {}
                : () async {
                    setState(
                      () => _activeActionKeys.add('pay_host_pp_$planId'),
                    );
                    try {
                      await _startHostRazorpayDirectPaymentInLiveFeed(
                        partyPlanId: planId,
                        venueName: venueName,
                        orderId: hostOrderId,
                        depositAmount: depositAmt,
                        onSuccess: () async {
                          _optimisticallyUpdatePartyPlanPayment(
                            planId: planId,
                            isHost: true,
                          );
                          await _loadFeed(showLoader: false);
                        },
                      );
                    } finally {
                      if (mounted) {
                        setState(
                          () =>
                              _activeActionKeys.remove('pay_host_pp_$planId'),
                        );
                      }
                    }
                  },
          ),
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ),
          ),
        ];
      } else if (isConfirmed) {
        final joiner =
            (acceptedJoinerRequest != null &&
                acceptedJoinerRequest['requester'] is Map)
            ? acceptedJoinerRequest['requester'] as Map<String, dynamic>
            : <String, dynamic>{};
        final joinerName =
            '${joiner["firstName"] ?? "Party Partner"} ${joiner["lastName"] ?? ""}'
                .trim();
        final joinerPhoto =
            joiner['profileImageUrl'] ?? joiner['profilePhotoUrl'];
        final joinerId =
            joiner['id'] ?? acceptedJoinerRequest?['requesterId'] ?? '';

        title = '🎉 Match Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body =
            'Your Party Plan with $joinerName at $venueName is confirmed. Both deposits paid • Chat unlocked.';
        senderUser = joiner.isNotEmpty ? joiner : hostCreator;
        avatarUrl = joinerPhoto ?? hostPhoto;

        partnerUser = joiner.isNotEmpty ? joiner : null;
        partnerRoleLabel = 'Partner:';
        statusSummary = 'Both Deposits Paid • Chat Unlocked';

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
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else if (acceptedJoinerRequest != null &&
          (acceptedJoinerRequest['status'] == 'accepted' ||
              acceptedJoinerRequest['status'] == 'payment_pending')) {
        final joiner = (acceptedJoinerRequest['requester'] is Map)
            ? acceptedJoinerRequest['requester'] as Map<String, dynamic>
            : <String, dynamic>{};
        final joinerName =
            '${joiner["firstName"] ?? "Participant"} ${joiner["lastName"] ?? ""}'
                .trim();
        final reqId = acceptedJoinerRequest['id']?.toString() ?? '';

        final bool isPrivateMatched =
            isPrivatePlan ||
            (selectedUserIdsList.contains(
              joiner['id']?.toString() ??
                  acceptedJoinerRequest['requesterId']?.toString(),
            ));

        title = isPrivateMatched
            ? '⏳ Invite Accepted — Awaiting Deposit'
            : '⏳ Approved — Awaiting Payment';
        badge = 'AWAITING PAYMENT';
        body = isPrivateMatched
            ? '$joinerName accepted your private invite. Waiting for safety deposit payment to unlock chat.'
            : 'You approved $joinerName. Waiting for safety deposit payment to unlock chat.';
        partnerUser = joiner.isNotEmpty ? joiner : null;
        partnerRoleLabel = 'Partner:';
        final isRevokingJoiner = _activeActionKeys.contains('reject_party_$reqId');
        actionsList = [
          NotificationAction(
            label: isRevokingJoiner ? 'Revoking...' : 'Revoke',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            isLoading: isRevokingJoiner,
            color: Colors.grey[200],
            onTap: isRevokingJoiner ? () {} : () => _handleRejectPartyPlan(reqId),
          ),
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ),
          ),
        ];
      } else if (isPrivatePlan ||
          (pendingOutboundInvites.isNotEmpty &&
              pendingIncomingRequests.isEmpty)) {
        final inviteCount = pendingOutboundInvites.isNotEmpty
            ? pendingOutboundInvites.length
            : (selectedUserIdsList.isNotEmpty ? selectedUserIdsList.length : 1);
        final firstInvitee = pendingOutboundInvites.isNotEmpty
            ? pendingOutboundInvites.first['requester']
            : null;
        final inviteeName =
            (firstInvitee is Map && firstInvitee['firstName'] != null)
            ? '${firstInvitee["firstName"]} ${firstInvitee["lastName"] ?? ""}'
                  .trim()
            : 'your invited friends';

        title = '💌 Private Invitations Sent';
        badge = 'INVITATIONS SENT';
        accent = const Color(0xFF7C3AED);
        body = inviteCount == 1
            ? 'You privately invited $inviteeName to your Party Plan at $venueName. Waiting for them to accept.'
            : inviteCount > 1
            ? 'You privately invited $inviteCount friends to your Party Plan at $venueName. Waiting for them to accept.'
            : 'Your Private Party Plan at $venueName is active. Waiting for your invited friends to accept.';
        statusSummary = 'Awaiting Friend Response';
        actionsList = [
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
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
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else if (pendingIncomingRequests.isNotEmpty) {
        final firstReq = pendingIncomingRequests.first;
        final reqUser = (firstReq['requester'] is Map)
            ? firstReq['requester'] as Map<String, dynamic>
            : <String, dynamic>{};
        final reqUserName =
            '${reqUser["firstName"] ?? "A user"} ${reqUser["lastName"] ?? ""}'
                .trim();

        if (pendingIncomingRequests.length == 1) {
          title = '📥 New Party Plan Request';
          badge = 'NEW REQUEST';
          body =
              '$reqUserName requested to join your Party Plan at $venueName.';
          senderUser = reqUser.isNotEmpty ? reqUser : hostCreator;
          avatarUrl = reqUser['profileImageUrl'] ?? reqUser['profilePhotoUrl'];

          partnerUser = reqUser.isNotEmpty ? reqUser : null;
          partnerRoleLabel = 'Request from:';
          statusSummary = isBothPlan
              ? 'Public Request Received'
              : 'Request Received';

          actionsList = [
            NotificationAction(
              label: 'View Request',
              icon: Icons.open_in_new_rounded,
              isPrimary: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyPlanDetailScreen(plan: planMap),
                ),
              ).then((_) => _loadFeed(showLoader: false)),
            ),
            NotificationAction(
              label: 'Review Requests',
              icon: Icons.people_alt_rounded,
              isPrimary: false,
              color: Colors.grey[200],
              onTap: () => _showReviewPartyPlanRequestsModal(
                planMap,
                pendingIncomingRequests,
              ),
            ),
          ];
        } else {
          title = '📥 Join Requests Received';
          badge = 'REQUESTS (${pendingIncomingRequests.length})';
          body =
              '${pendingIncomingRequests.length} users requested to join your Party Plan at $venueName.';
          statusSummary = '${pendingIncomingRequests.length} Pending Requests';
          actionsList = [
            NotificationAction(
              label: 'Review Requests (${pendingIncomingRequests.length})',
              icon: Icons.people_alt_rounded,
              isPrimary: true,
              onTap: () => _showReviewPartyPlanRequestsModal(
                planMap,
                pendingIncomingRequests,
              ),
            ),
            NotificationAction(
              label: 'View Plan',
              icon: Icons.open_in_new_rounded,
              isPrimary: false,
              color: Colors.grey[200],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyPlanDetailScreen(plan: planMap),
                ),
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
        statusSummary = 'Live & Open';
        actionsList = [
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
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
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      }
    } else {
      userRoleLabel = 'Hosted by';
      partnerUser = hostCreator.isNotEmpty ? hostCreator : null;
      partnerRoleLabel = 'Host:';

      final planVis = planMap['visibility']?.toString().toUpperCase() ?? '';
      final selectedUsers = planMap['selectedUsers'] ?? planMap['selectedUserIds'];
      final bool inSelectedUsers = (selectedUsers is List &&
              selectedUsers.any((u) => u?.toString() == currentUserId)) ||
          selectedUserIdsList.contains(currentUserId);
      final bool isExplicitInvite = myRequest?['isInvite'] == true ||
          myRequest?['requestType'] == 'private_invite' ||
          myRequest?['type'] == 'party_plan_invitation' ||
          myRequest?['isPrivateInvite'] == true;
      final bool isPrivateInvite = inSelectedUsers ||
          (planVis == 'PRIVATE' && myRequest != null) ||
          isExplicitInvite;

      final myStatus = (myRequest?['status'] ?? '').toString().toLowerCase();

      final bool hasAnotherPartner =
          !isHost &&
          !isConfirmed &&
          ((planMap['matchedRequestId'] != null &&
                  planMap['matchedRequestId'].toString().isNotEmpty &&
                  (myRequest == null ||
                      myRequest['id']?.toString() !=
                          planMap['matchedRequestId'].toString())) ||
              (planMap['partnerId'] != null &&
                  planMap['partnerId'].toString().isNotEmpty &&
                  planMap['partnerId'].toString() != currentUserId) ||
              myRequest?['cancellationReason'] == 'partner_already_selected' ||
              myRequest?['reason'] == 'partner_already_selected' ||
              entries.any(
                (e) =>
                    e['eventType'] == 'plan_unavailable' ||
                    e['reason'] == 'partner_already_selected' ||
                    e['status'] == 'NO_LONGER_AVAILABLE' ||
                    e['metadata']?['reason'] == 'partner_already_selected' ||
                    (e['title'] != null &&
                        e['title'].toString().contains('Unavailable')),
              ));

      if (isConfirmed) {
        title = '🎉 Match Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body =
            'Your Party Plan with $hostName at $venueName is confirmed. Both deposits paid • Chat unlocked.';
        final otherId = planHostId.isNotEmpty
            ? planHostId
            : (hostCreator['id'] ?? '');
        statusSummary = 'Both Deposits Paid • Chat Unlocked';

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
              // Enrich planMap with already-resolved host data so the ticket
              // screen can render the host profile instantly (no async wait).
              final enrichedPlan = Map<String, dynamic>.from(planMap);
              if (enrichedPlan['host'] == null && hostUserObj.isNotEmpty) {
                enrichedPlan['host'] = Map<String, dynamic>.from(hostUserObj);
              }
              if (enrichedPlan['creator'] == null && hostCreator.isNotEmpty) {
                enrichedPlan['creator'] = Map<String, dynamic>.from(
                  hostCreator,
                );
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyPlanTicketScreen(
                    request: myRequest ?? enrichedPlan,
                    plan: enrichedPlan,
                    isHost: false,
                  ),
                ),
              );
            },
          ),
          NotificationAction(
            label: 'Cancel Plan',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.red[50],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else if (hasAnotherPartner) {
        title = 'Party Plan Unavailable';
        badge = 'NO LONGER AVAILABLE';
        accent = const Color(0xFFEF4444);
        body =
            'This Party Plan is no longer available.\n\n$hostName has joined with another partner.\n\nFind another Party Plan or create your own.';
        statusSummary = 'Unavailable';

        actionsList = [
          NotificationAction(
            label: 'Find Another Plan',
            icon: Icons.explore_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlanHubScreen()),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
          NotificationAction(
            label: 'Create Your Own',
            icon: Icons.add_circle_outline_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PlanHubScreen(autoShowCreatePlan: true),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else if (myStatus == 'accepted' || myStatus == 'payment_pending') {
        final reqId = myRequest?['id']?.toString() ?? '';
        title = isPrivateInvite
            ? '💌 Invite Accepted! Pay Deposit'
            : '✅ Approved! Pay Safety Deposit';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFF8B5CF6);
        body = isPrivateInvite
            ? 'You accepted $hostName\'s private invite! Pay safety deposit within ${timeRemainingText.isNotEmpty ? timeRemainingText : countdownLabel} to confirm your match.'
            : '$hostName accepted your request! Pay your safety deposit within ${timeRemainingText.isNotEmpty ? timeRemainingText : countdownLabel} to confirm match.';
        statusSummary = timeRemainingText.isNotEmpty
            ? timeRemainingText
            : 'Window: $countdownLabel';

        final isPayingJoiner = _activeActionKeys.contains(
          'pay_joiner_pp_$planId',
        );
        final isDecliningOrWithdrawing =
            _activeActionKeys.contains('FEED_CANCEL_REQ:$reqId') ||
            _activeActionKeys.contains('reject_party_$reqId');

        actionsList = [
          NotificationAction(
            label: isPayingJoiner
                ? 'Opening Gateway...'
                : (isPaymentExpired
                    ? 'Payment Window Expired'
                    : 'Pay Deposit (₹99) • $countdownLabel'),
            icon: Icons.payment_rounded,
            isPrimary: true,
            isLoading: isPayingJoiner,
            onTap: (isPayingJoiner || isPaymentExpired)
                ? () {}
                : () async {
                    setState(
                      () => _activeActionKeys.add('pay_joiner_pp_$planId'),
                    );
                    try {
                      await _startJoinerRazorpayDirectPaymentInLiveFeed(
                        partyPlanId: planId,
                        requestId: reqId,
                        venueName: venueName,
                        depositAmount: 99.0,
                        onSuccess: () async {
                          _optimisticallyUpdatePartyPlanPayment(
                            planId: planId,
                            isHost: false,
                            requestId: reqId,
                          );
                          await _loadFeed(showLoader: false);
                        },
                      );
                    } finally {
                      if (mounted) {
                        setState(
                          () => _activeActionKeys.remove(
                            'pay_joiner_pp_$planId',
                          ),
                        );
                      }
                    }
                  },
          ),
          NotificationAction(
            label: 'View Plan',
            icon: Icons.open_in_new_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              final enrichedPlan = Map<String, dynamic>.from(planMap);
              if (reqId.isNotEmpty) {
                enrichedPlan['requestId'] = reqId;
                enrichedPlan['activeRequestId'] = reqId;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyPlanDetailScreen(plan: enrichedPlan),
                ),
              ).then((_) => _loadFeed(showLoader: false));
            },
          ),
          NotificationAction(
            label: isDecliningOrWithdrawing
                ? (isPrivateInvite ? 'Declining...' : 'Withdrawing...')
                : (isPrivateInvite ? 'Decline' : 'Withdraw'),
            icon: Icons.cancel_rounded,
            isPrimary: false,
            isLoading: isDecliningOrWithdrawing,
            color: Colors.grey[200],
            onTap: isDecliningOrWithdrawing
                ? () {}
                : () => isPrivateInvite
                    ? _handleRejectPartyPlan(reqId)
                    : _handleCancelMyRequest(reqId),
          ),
        ];
      } else if (isPrivateInvite &&
          (myStatus == 'pending' || myStatus.isEmpty)) {
        final reqId = myRequest?['id']?.toString() ?? planId;
        title = '💌 Private Party Invite!';
        badge = 'INVITE';
        accent = const Color(0xFF7C3AED);
        body =
            '$hostName privately invited you to their Party Plan at $venueName. Accept to proceed!';
        statusSummary = 'Private Invite';

        final isAcceptingInvite = _activeActionKeys.contains(
          'accept_invite_$reqId',
        );
        final isDecliningInvite = _activeActionKeys.contains(
          'reject_party_$reqId',
        );
        actionsList = [
          NotificationAction(
            label: isAcceptingInvite ? 'Accepting...' : 'Accept',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            isLoading: isAcceptingInvite,
            onTap: (isAcceptingInvite || isDecliningInvite)
                ? () {}
                : () => _handleAcceptPartyPlanInvite(reqId),
          ),
          NotificationAction(
            label: isDecliningInvite ? 'Declining...' : 'Decline',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            isLoading: isDecliningInvite,
            color: Colors.grey[200],
            onTap: (isAcceptingInvite || isDecliningInvite)
                ? () {}
                : () => _handleRejectPartyPlan(reqId),
          ),
        ];
      } else if (myStatus == 'pending') {
        final reqId = myRequest?['id']?.toString() ?? '';
        title = '🤝 Request Sent';
        badge = 'REQUEST SENT';
        body =
            'Request sent to $hostName for Party Plan at $venueName. Waiting for host approval.';
        final isWithdrawingPending =
            _activeActionKeys.contains('FEED_CANCEL_REQ:$reqId');
        actionsList = [
          NotificationAction(
            label: isWithdrawingPending ? 'Withdrawing...' : 'Withdraw Request',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            isLoading: isWithdrawingPending,
            color: Colors.grey[200],
            onTap: isWithdrawingPending
                ? () {}
                : () => _handleCancelMyRequest(reqId),
          ),
        ];
      } else if (myStatus == 'rejected' || myStatus == 'declined') {
        title = '❌ Request Declined';
        badge = 'DECLINED';
        accent = const Color(0xFF9CA3AF);
        body =
            'Your Party Plan request at $venueName was declined by $hostName.';
        statusSummary = 'Declined';
        actionsList = [
          NotificationAction(
            label: 'Request to Join',
            icon: Icons.person_add_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else if (myStatus == 'withdrawn' || myStatus == 'cancelled') {
        title = '↩️ Request Cancelled';
        badge = 'CANCELLED';
        accent = const Color(0xFF9CA3AF);
        body = 'You cancelled your request for Party Plan at $venueName.';
        statusSummary = 'Cancelled';
        actionsList = [
          NotificationAction(
            label: 'Request to Join',
            icon: Icons.person_add_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      } else {
        final bool superLikedYou = planMap['superLikedYou'] == true;
        final bool iSuperlikedThem = planMap['iSuperlikedThem'] == true;
        title = superLikedYou
            ? '⭐ Let\'s party at $venueName!'
            : (iSuperlikedThem
                  ? '💫 $hostName just posted a plan!'
                  : '🎉 Party Plan at $venueName');
        badge = superLikedYou
            ? 'SUPER LIKED YOU'
            : (iSuperlikedThem ? 'YOU SUPER LIKED THEM' : 'PARTY PLAN');
        accent = (superLikedYou || iSuperlikedThem)
            ? const Color(0xFF8B5CF6)
            : accent;
        body = superLikedYou
            ? '💜 $hostName Super Liked you • $formattedDateTime'
            : (iSuperlikedThem
                  ? '💫 Someone you Super Liked is hosting • $formattedDateTime'
                  : (formattedDateTime.isNotEmpty
                        ? '$hostName is hosting • $formattedDateTime'
                        : '$hostName is hosting a Party Plan at $venueName.'));
        actionsList = [
          NotificationAction(
            label: 'Request to Join',
            icon: Icons.person_add_rounded,
            isPrimary: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanDetailScreen(plan: planMap),
              ),
            ).then((_) => _loadFeed(showLoader: false)),
          ),
        ];
      }
    }

    DateTime latestCreatedAt = DateTime(2000);
    bool allRead = true;
    for (final e in entries) {
      final dt = _parseDateTime(
        e['lastActivityAt'] ??
            e['updatedAt'] ??
            e['createdAt'] ??
            e['postedAt'],
      );
      if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
      final eId = e['id']?.toString() ?? '';
      final read =
          e['read'] == true ||
          e['isRead'] == true ||
          _localReadNotificationIds.contains(eId) ||
          ApiService.localReadRequestIds.contains(eId);
      if (!read) allRead = false;
    }
    if (planMap['lastActivityAt'] != null) {
      try {
        final dt = _parseDateTime(planMap['lastActivityAt']);
        if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
      } catch (_) {}
    }
    if (_localReadNotificationIds.contains('pp_$planId') ||
        _localReadNotificationIds.contains(planId) ||
        ApiService.localReadRequestIds.contains('pp_$planId') ||
        ApiService.localReadRequestIds.contains(planId)) {
      allRead = true;
    }
    if (badge == 'ACTION REQUIRED' ||
        badge == 'INVITE' ||
        badge == 'NEW REQUEST') {
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
      rawData: {
        'id': planId,
        'plan': planMap,
        'pendingIncomingRequests': pendingIncomingRequests,
        ...planMap,
      },
      userRoleLabel: userRoleLabel,
      partnerUser: partnerUser,
      partnerRoleLabel: partnerRoleLabel,
      statusSummary: statusSummary,
    );
  }

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
      } else if (e['requestType'] == 'stranger_meet' ||
          e['category'] == 'stranger_meet') {
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
    final venueName =
        venue['name']?.toString() ??
        meetMap['venueName']?.toString() ??
        'Venue';

    final hostCreator = (meetMap['user'] is Map)
        ? meetMap['user'] as Map<String, dynamic>
        : (meetMap['host'] is Map
              ? meetMap['host'] as Map<String, dynamic>
              : <String, dynamic>{});
    final hostName =
        '${hostCreator["firstName"] ?? meetMap["hostName"] ?? "Host"} ${hostCreator["lastName"] ?? ""}'
            .trim();

    String? rawMeetHostPhoto =
        _extractUserPhoto(hostCreator) ??
        _extractUserPhoto(meetMap['user']) ??
        _extractUserPhoto(meetMap['host']) ??
        _extractUserPhoto(meetMap['creator']) ??
        _extractUserPhoto(meetMap['sender']) ??
        _extractUserPhoto(meetMap);

    if (rawMeetHostPhoto == null || rawMeetHostPhoto.isEmpty) {
      for (final e in entries) {
        rawMeetHostPhoto =
            _extractUserPhoto(e['user']) ??
            _extractUserPhoto(e['host']) ??
            _extractUserPhoto(e['creator']) ??
            _extractUserPhoto(e['sender']) ??
            _extractUserPhoto(
              e['data'] is Map ? _extractUserPhoto(e['data']['user']) : null,
            ) ??
            _extractUserPhoto(
              e['data'] is Map ? _extractUserPhoto(e['data']['host']) : null,
            ) ??
            _extractUserPhoto(e['data']) ??
            _extractUserPhoto(e);
        if (rawMeetHostPhoto != null && rawMeetHostPhoto.isNotEmpty) break;
      }
    }
    final hostPhoto = rawMeetHostPhoto != null
        ? ApiService.formatImageUrl(rawMeetHostPhoto)
        : null;

    final String meetHostId =
        (meetMap['userId'] ??
                meetMap['user_id'] ??
                meetMap['hostId'] ??
                meetMap['host_id'] ??
                hostCreator['id'] ??
                (meetMap['host'] is Map ? meetMap['host']['id'] : null) ??
                '')
            .toString();
    final bool isHost =
        currentUserId.isNotEmpty &&
        (meetHostId == currentUserId ||
            meetMap['role'] == 'host' ||
            meetMap['isHost'] == true);

    Map<String, dynamic>? myRequest;
    final List<Map<String, dynamic>> pendingIncomingRequests = [];
    Map<String, dynamic>? paidJoinerRecord;

    for (final e in entries) {
      final reqType = (e['type'] ?? e['requestType'] ?? '').toString();
      final status = (e['status'] ?? '').toString().toLowerCase();
      final pStatus = (e['joinerPaymentStatus'] ?? e['paymentStatus'] ?? '')
          .toString()
          .toLowerCase();
      final String eRequesterId =
          (e['requesterId'] ??
                  e['requester']?['id'] ??
                  e['userId'] ??
                  e['actorUserId'] ??
                  e['data']?['userId'] ??
                  '')
              .toString();
      final String title = (e['title'] ?? '').toString().toLowerCase();

      if (!isHost &&
          (reqType == 'my_request' ||
              reqType == 'stranger_meet_join' ||
              (eRequesterId == currentUserId &&
                  reqType != 'stranger_meet_deposit' &&
                  reqType != 'strangers_meet_deposit_paid') ||
              (e['isMyRequest'] == true) ||
              reqType.contains('request_sent') ||
              title.contains('request sent'))) {
        myRequest = e;
      }
      if (reqType == 'incoming_request' ||
          (isHost && e['requester'] != null && eRequesterId != currentUserId)) {
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
    final rawDateTime =
        meetMap['eventDateTime'] ??
        meetMap['planDate'] ??
        meetMap['partyDate'] ??
        meetMap['bookingDate'];
    final rawStartTime = meetMap['startTime'] ?? meetMap['time'];
    final parsedEventDate = _parseEventDateTime(rawDateTime, rawStartTime);
    if (parsedEventDate != null) {
      try {
        const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const monthNames = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final w = weekdayNames[parsedEventDate.weekday - 1];
        final m = monthNames[parsedEventDate.month - 1];
        final hour = parsedEventDate.hour % 12 == 0
            ? 12
            : parsedEventDate.hour % 12;
        final ampm = parsedEventDate.hour >= 12 ? 'PM' : 'AM';
        final minute = parsedEventDate.minute.toString().padLeft(2, '0');
        formattedDateTime =
            '$w, ${parsedEventDate.day} $m • $hour:$minute $ampm';
      } catch (_) {}
    }

    bool isExpired = false;
    if (parsedEventDate != null &&
        DateTime.now().isAfter(parsedEventDate.add(const Duration(hours: 4)))) {
      isExpired = true;
    }
    final meetStatus = (meetMap['status'] ?? '').toString().toLowerCase();
    final hostPayStatus = (meetMap['paymentStatus'] ?? '')
        .toString()
        .toLowerCase();
    if (meetStatus == 'completed' ||
        meetStatus == 'expired' ||
        meetStatus == 'cancelled') {
      if (meetStatus == 'expired') isExpired = true;
    }

    final dynamic rawCharges =
        meetMap['chargesPerHead'] ?? myRequest?['chargesPerHead'] ?? 0.0;
    final double chargesPerHead = rawCharges is num
        ? rawCharges.toDouble()
        : (double.tryParse(rawCharges.toString()) ?? 0.0);

    Color accent = const Color(0xFF6366F1);
    String title = '🤝 Stranger Meet at $venueName';
    String body = formattedDateTime.isNotEmpty
        ? '📅 $formattedDateTime'
        : 'Stranger Meet at $venueName';
    String badge = 'STRANGER MEET';
    List<NotificationAction>? actionsList;
    Map<String, dynamic>? senderUser = hostCreator;
    String? avatarUrl = hostPhoto;

    String? userRoleLabel = isHost ? '👑 Your Stranger Meet' : 'Hosted by';
    Map<String, dynamic>? partnerUser;
    String? partnerRoleLabel;
    String? statusSummary;

    final rawExpectedEnd =
        meetMap['expectedEndAt'] ?? meetMap['expected_end_at'];
    final DateTime? expectedEnd = rawExpectedEnd != null
        ? DateTime.tryParse(rawExpectedEnd.toString())?.toLocal()
        : null;
    final String endFormatted = expectedEnd != null
        ? DateFormat('hh:mm a').format(expectedEnd)
        : '';

    if (isExpired) {
      accent = const Color(0xFF9CA3AF);
      badge = 'EXPIRED';
      title = '🤝 Stranger Meet Expired ⌛';
      body = 'This Stranger Meet at $venueName has ended / expired.';
      statusSummary = 'Meet Expired';
      actionsList = null;
    } else if (meetStatus == 'start_confirmation_pending') {
      title = '🟢 START CONFIRMATION REQUIRED';
      badge = 'ACTION REQUIRED';
      accent = const Color(0xFF8B5CF6);
      body =
          'Scheduled: $formattedDateTime at $venueName. Has your meetup started?';
      statusSummary = 'Start Confirmation Required';

      if (isHost) {
        userRoleLabel = '👑 Your Stranger Meet';
        final isMarkingNotStarted = _activeActionKeys.contains('sm_not_started_$meetId');
        actionsList = [
          NotificationAction(
            label: 'Started',
            icon: Icons.play_circle_fill_rounded,
            isPrimary: true,
            onTap: () {
              StrangersMeetStartDialog.show(
                context,
                meetId: meetId,
                subject: meetMap['subject']?.toString() ?? 'Strangers Meet',
                venueName: venueName,
                eventDateTime: parsedEventDate ?? DateTime.now(),
                onStarted: () => _loadFeed(),
              );
            },
          ),
          NotificationAction(
            label: isMarkingNotStarted ? 'Marking...' : 'Not Started',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            isLoading: isMarkingNotStarted,
            color: Colors.redAccent,
            onTap: isMarkingNotStarted ? () {} : () => _handleMarkStrangersMeetNotStarted(meetId),
          ),
        ];
      } else {
        userRoleLabel = 'Hosted by';
        partnerUser = hostCreator.isNotEmpty ? hostCreator : null;
        partnerRoleLabel = 'Host:';
        final otherId = meetHostId.isNotEmpty
            ? meetHostId
            : (hostCreator['id'] ?? '');

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
        ];
      }
    } else if (meetStatus == 'end_confirmation_pending') {
      title = '🏁 END CONFIRMATION REQUIRED';
      badge = 'CONFIRM END';
      accent = const Color(0xFFF59E0B);
      body =
          'Expected end time ($endFormatted) reached. Has your meetup ended?';
      statusSummary = 'End Confirmation Required';

      if (isHost) {
        userRoleLabel = '👑 Your Stranger Meet';
        final isEndingMeet = _activeActionKeys.contains('sm_end_$meetId');
        actionsList = [
          NotificationAction(
            label: isEndingMeet ? 'Ending...' : 'Yes, Ended',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            isLoading: isEndingMeet,
            onTap: isEndingMeet ? () {} : () => _handleConfirmStrangersMeetEndedDirect(meetId),
          ),
          NotificationAction(
            label: 'Still Going',
            icon: Icons.more_time_rounded,
            isPrimary: false,
            color: const Color(0xFFF59E0B),
            onTap: () {
              StrangersMeetEndDialog.show(
                context,
                meetId: meetId,
                subject: meetMap['subject']?.toString() ?? 'Strangers Meet',
                venueName: venueName,
                expectedEndAt: expectedEnd,
                onEnded: () => _loadFeed(),
                onExtended: () => _loadFeed(),
              );
            },
          ),
        ];
      } else {
        userRoleLabel = 'Hosted by';
        partnerUser = hostCreator.isNotEmpty ? hostCreator : null;
        partnerRoleLabel = 'Host:';
        final otherId = meetHostId.isNotEmpty
            ? meetHostId
            : (hostCreator['id'] ?? '');

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
        ];
      }
    } else if (meetStatus == 'needs_host_contact') {
      title = '⚠️ ACTION REQUIRED';
      badge = 'STATUS UNRESOLVED';
      accent = const Color(0xFFEF4444);
      body = isHost
          ? 'No start/end confirmation was received within 24h. Please update your status or our team will contact you.'
          : 'This meetup is currently under investigation by Lunara Admin.';
      statusSummary = 'Needs Host Contact';

      if (isHost) {
        userRoleLabel = '👑 Your Stranger Meet';
        actionsList = [
          NotificationAction(
            label: 'Update Status',
            icon: Icons.edit_calendar_rounded,
            isPrimary: true,
            onTap: () {
              StrangersMeetStartDialog.show(
                context,
                meetId: meetId,
                subject: meetMap['subject']?.toString() ?? 'Strangers Meet',
                venueName: venueName,
                eventDateTime: parsedEventDate ?? DateTime.now(),
                onStarted: () => _loadFeed(),
              );
            },
          ),
          NotificationAction(
            label: 'Not Started',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.redAccent,
            onTap: () => _handleMarkStrangersMeetNotStarted(meetId),
          ),
        ];
      }
    } else if (meetStatus == 'not_started') {
      title = '❌ Meetup Not Started';
      badge = 'NOT STARTED';
      accent = const Color(0xFF6B7280);
      body = 'This Strangers Meet at $venueName did not take place.';
      statusSummary = 'Not Started • Closed';
      actionsList = null;
    } else if (meetStatus == 'in_progress') {
      final startedFormatted = meetMap['startedAt'] != null
          ? DateFormat('hh:mm a').format(
              DateTime.tryParse(meetMap['startedAt'].toString())?.toLocal() ??
                  DateTime.now(),
            )
          : '';
      title = '🟢 Stranger Meet In Progress';
      badge = 'LIVE / IN PROGRESS';
      accent = const Color(0xFF3B82F6);
      body = startedFormatted.isNotEmpty
          ? 'Started at $startedFormatted • Expected end: ${endFormatted.isNotEmpty ? endFormatted : 'TBD'}'
          : 'Meetup is live at $venueName!';
      statusSummary = 'Started • In Progress';

      if (isHost) {
        userRoleLabel = '👑 Your Stranger Meet';
        actionsList = [
          NotificationAction(
            label: 'End Meet',
            icon: Icons.timer_outlined,
            isPrimary: true,
            color: const Color(0xFFF59E0B),
            onTap: () {
              StrangersMeetEndDialog.show(
                context,
                meetId: meetId,
                subject: meetMap['subject']?.toString() ?? 'Strangers Meet',
                venueName: venueName,
                expectedEndAt: expectedEnd,
                onEnded: () => _loadFeed(),
                onExtended: () => _loadFeed(),
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
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
        ];
      } else {
        userRoleLabel = 'Hosted by';
        partnerUser = hostCreator.isNotEmpty ? hostCreator : null;
        partnerRoleLabel = 'Host:';
        final otherId = meetHostId.isNotEmpty
            ? meetHostId
            : (hostCreator['id'] ?? '');

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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
        ];
      }
    } else if (meetStatus == 'host_confirmed_ended') {
      title = '🏁 Stranger Meet Ended';
      badge = 'AWAITING ADMIN VERIFICATION';
      accent = const Color(0xFFF59E0B);
      body = isHost
          ? 'You marked this meet as ended. Admin will verify and process host payout within 24 hours.'
          : 'This Stranger Meet has ended. Hope you had a great time!';
      statusSummary = isHost ? 'Awaiting Admin Verification' : 'Ended';
      userRoleLabel = isHost ? '👑 Your Stranger Meet' : 'Hosted by';
      actionsList = [
        NotificationAction(
          label: 'View Ticket',
          icon: Icons.confirmation_number_rounded,
          isPrimary: true,
          onTap: () {
            try {
              final req = StrangersMeetRequest.fromJson(meetMap);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetTicketScreen(request: req),
                ),
              );
            } catch (e) {
              debugPrint('Error parsing SM ticket: $e');
            }
          },
        ),
      ];
    } else if (meetStatus == 'admin_confirmed_ended') {
      title = '⏳ Meetup Verified';
      badge = 'SETTLEMENT IN 24H';
      accent = const Color(0xFF8B5CF6);
      body = isHost
          ? 'Admin verified meetup completion. Your payout will be settled to your account within 24 hours.'
          : 'This Stranger Meet has concluded.';
      statusSummary = isHost ? 'Settlement in 24 Hours' : 'Concluded';
      userRoleLabel = isHost ? '👑 Your Stranger Meet' : 'Hosted by';
      actionsList = [
        NotificationAction(
          label: 'View Ticket',
          icon: Icons.confirmation_number_rounded,
          isPrimary: true,
          onTap: () {
            try {
              final req = StrangersMeetRequest.fromJson(meetMap);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetTicketScreen(request: req),
                ),
              );
            } catch (e) {
              debugPrint('Error parsing SM ticket: $e');
            }
          },
        ),
      ];
    } else if (meetStatus == 'completed' || meetStatus == 'settled') {
      final amount =
          meetMap['settlementAmount'] ?? meetMap['settlement_amount'];
      final String settlementStr = amount != null
          ? '₹${double.tryParse(amount.toString())?.toStringAsFixed(0) ?? amount}'
          : '';
      title = '✓ Meetup Completed & Settled';
      badge = 'SETTLED & COMPLETED';
      accent = const Color(0xFF10B981);
      body = isHost
          ? (settlementStr.isNotEmpty
                ? 'Host payout of $settlementStr has been settled to your account.'
                : 'Your host payout has been settled.')
          : 'This Stranger Meet was successfully completed.';
      statusSummary = 'Settled & Completed';
      userRoleLabel = isHost ? '👑 Your Stranger Meet' : 'Hosted by';
      actionsList = [
        NotificationAction(
          label: 'View Ticket',
          icon: Icons.confirmation_number_rounded,
          isPrimary: true,
          onTap: () {
            try {
              final req = StrangersMeetRequest.fromJson(meetMap);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetTicketScreen(request: req),
                ),
              );
            } catch (e) {
              debugPrint('Error parsing SM ticket: $e');
            }
          },
        ),
      ];
    } else if (isHost) {
      userRoleLabel = '👑 Your Stranger Meet';

      if (meetStatus == 'pending' ||
          meetStatus == 'request_sent' ||
          meetStatus == 'pending_approval') {
        title = '🤝 Request Sent';
        badge = 'REQUEST SENT';
        accent = const Color(0xFF8B5CF6);
        body =
            'Request sent to Admin for Stranger Meet at $venueName. Waiting for admin approval.';
        statusSummary = 'Waiting for Admin Approval';
        actionsList = null;
      } else if ((meetStatus == 'approved' ||
              meetStatus == 'accepted' ||
              meetStatus == 'payment_pending') &&
          (hostPayStatus == 'unpaid' ||
              hostPayStatus == 'pending' ||
              hostPayStatus.isEmpty)) {
        title = '⚡ Action Required: Pay Host Deposit';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFF8B5CF6);
        final rawDep =
            meetMap['paymentAmount'] ??
            meetMap['payment_amount'] ??
            meetMap['adminPaymentAmount'] ??
            meetMap['admin_payment_amount'] ??
            meetMap['totalAmount'] ??
            meetMap['depositAmount'] ??
            myRequest?['paymentAmount'] ??
            myRequest?['payment_amount'];
        final double deposit = rawDep is num
            ? rawDep.toDouble()
            : (double.tryParse((rawDep ?? '0').toString()) ?? 0.0);
        final feeLabel = deposit > 0 ? '₹${deposit.toStringAsFixed(0)}' : '';
        body = deposit > 0
            ? 'Admin approved your Stranger Meet! Pay deposit of $feeLabel to make your Stranger Meet live at $venueName!'
            : 'Admin approved your Stranger Meet at $venueName!';
        statusSummary = 'Deposit Pending';
        actionsList = [
          NotificationAction(
            label: deposit > 0 ? 'Pay Deposit $feeLabel' : 'Pay Deposit',
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
                      onPaymentSuccess: () {
                        _optimisticallyUpdateStrangerMeetPayment(
                          meetId: req.id,
                          isHost: true,
                        );
                        _loadFeed(showLoader: false);
                      },
                      isJoinPayment: false,
                    ),
                  ),
                ).then((_) => _loadFeed(showLoader: false));
              } catch (e) {
                debugPrint('Error parsing SM host payment: $e');
              }
            },
          ),
        ];
      } else if (meetMap['hostCancellation'] is Map) {
        final hostCancel = meetMap['hostCancellation'] as Map<String, dynamic>;
        final String cancelStatus = hostCancel['status']?.toString() ?? '';
        final String hostRefundStatus =
            hostCancel['hostRefundStatus']?.toString() ?? '';
        final double hostRefundAmt =
            double.tryParse((hostCancel['hostRefundAmount'] ?? 0).toString()) ??
            0.0;
        final String hostRefundDest =
            hostCancel['hostRefundDestination']?.toString() ??
            'UPI / Bank Account';
        final String hostRef =
            hostCancel['hostSettlementTransactionId']?.toString() ?? '';

        if (hostRefundStatus == 'HOST_REFUND_PENDING_SETTLEMENT') {
          title = '💰 STRANGERS MEET REFUND';
          badge = 'PENDING';
          accent = const Color(0xFFF59E0B);
          body =
              'Cancellation approved\nRefund amount: ₹${hostRefundAmt.toStringAsFixed(0)}\nDestination: $hostRefundDest\nSettlement: Processing within 24 hours';
          statusSummary = 'Pending Settlement (within 24h)';
          actionsList = [
            NotificationAction(
              label: 'View Ticket',
              icon: Icons.confirmation_number_rounded,
              isPrimary: true,
              onTap: () {
                try {
                  final req = StrangersMeetRequest.fromJson(meetMap);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StrangersMeetTicketScreen(request: req),
                    ),
                  );
                } catch (e) {
                  debugPrint('Error opening meet ticket: $e');
                }
              },
            ),
          ];
        } else if (hostRefundStatus == 'PAID') {
          title = '💰 STRANGERS MEET REFUND';
          badge = 'SETTLED';
          accent = const Color(0xFF10B981);
          body =
              'Cancellation approved\nRefund amount: ₹${hostRefundAmt.toStringAsFixed(0)}\nDestination: $hostRefundDest\nStatus: ✓ Amount Settled${hostRef.isNotEmpty ? '\nReference: $hostRef' : ''}';
          statusSummary = 'Settled';
          actionsList = [
            NotificationAction(
              label: 'View Ticket',
              icon: Icons.confirmation_number_rounded,
              isPrimary: true,
              onTap: () {
                try {
                  final req = StrangersMeetRequest.fromJson(meetMap);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StrangersMeetTicketScreen(request: req),
                    ),
                  );
                } catch (e) {
                  debugPrint('Error opening meet ticket: $e');
                }
              },
            ),
          ];
        } else if (cancelStatus == 'PENDING_ADMIN_REVIEW') {
          title = '⏳ Cancellation Requested';
          badge = 'AWAITING ADMIN REVIEW';
          accent = const Color(0xFFF59E0B);
          body =
              'Your cancellation request has been submitted and is waiting for admin approval.';
          statusSummary = 'Waiting for admin approval';
          actionsList = [
            NotificationAction(
              label: 'View Ticket',
              icon: Icons.confirmation_number_rounded,
              isPrimary: true,
              onTap: () {
                try {
                  final req = StrangersMeetRequest.fromJson(meetMap);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StrangersMeetTicketScreen(request: req),
                    ),
                  );
                } catch (e) {
                  debugPrint('Error opening meet ticket: $e');
                }
              },
            ),
          ];
        } else {
          title = 'Stranger Meet Cancelled';
          badge = 'CANCELLED';
          accent = const Color(0xFFEF4444);
          final String hostWalletNote = hostRefundStatus == 'WALLET_CREDITED'
              ? ' Host deposit refund of ₹${hostRefundAmt.toStringAsFixed(0)} credited to Lunara Wallet.'
              : '';
          body =
              'You cancelled this Stranger Meet at $venueName. Participant refunds have been processed.$hostWalletNote';
          statusSummary = 'Cancelled • Refunds Processed';
          actionsList = [
            NotificationAction(
              label: 'View Ticket',
              icon: Icons.confirmation_number_rounded,
              isPrimary: true,
              onTap: () {
                try {
                  final req = StrangersMeetRequest.fromJson(meetMap);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StrangersMeetTicketScreen(request: req),
                    ),
                  );
                } catch (e) {
                  debugPrint('Error opening meet ticket: $e');
                }
              },
            ),
          ];
        }
      } else if (meetStatus == 'cancelled') {
        title = 'Stranger Meet Cancelled';
        badge = 'CANCELLED';
        accent = const Color(0xFFEF4444);
        body = 'This Stranger Meet at $venueName was cancelled.';
        statusSummary = 'Cancelled';
        actionsList = [
          NotificationAction(
            label: 'View Ticket',
            icon: Icons.confirmation_number_rounded,
            isPrimary: true,
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error opening meet ticket: $e');
              }
            },
          ),
        ];
      } else if (meetMap['pendingCancellationRequests'] is List &&
          (meetMap['pendingCancellationRequests'] as List).isNotEmpty) {
        final pendingCancellations = List<Map<String, dynamic>>.from(
          meetMap['pendingCancellationRequests'],
        );
        final firstCancel = pendingCancellations.first;
        final cId = firstCancel['cancellationId']?.toString() ?? '';
        final cName = firstCancel['name']?.toString() ?? 'Participant';
        final cPaid = firstCancel['paidAmount'] != null
            ? ' (₹${firstCancel['paidAmount']})'
            : '';

        title = '⚠️ Cancellation Requested';
        badge = 'CANCELLATION REQUEST';
        accent = const Color(0xFFF59E0B);
        body = '$cName requested cancellation from your Stranger Meet$cPaid.';
        statusSummary = 'Host Approval Required';
        final smAcceptCancelKey = 'sm_cancel_accept_$cId';
        final smRejectCancelKey = 'sm_cancel_reject_$cId';
        final isSmAcceptingCancel = _activeActionKeys.contains(
          smAcceptCancelKey,
        );
        final isSmRejectingCancel = _activeActionKeys.contains(
          smRejectCancelKey,
        );

        actionsList = [
          NotificationAction(
            label: isSmAcceptingCancel ? 'Accepting...' : 'Accept Cancellation',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            isLoading: isSmAcceptingCancel,
            onTap: (isSmAcceptingCancel || isSmRejectingCancel)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(smAcceptCancelKey));
                    try {
                      await _handleStrangersMeetCancellationAction(
                        meetId,
                        cId,
                        'accept',
                      );
                    } finally {
                      if (mounted) {
                        setState(
                          () => _activeActionKeys.remove(smAcceptCancelKey),
                        );
                      }
                    }
                  },
          ),
          NotificationAction(
            label: isSmRejectingCancel ? 'Rejecting...' : 'Reject',
            icon: Icons.cancel_rounded,
            isPrimary: false,
            isLoading: isSmRejectingCancel,
            color: Colors.grey[200],
            onTap: (isSmAcceptingCancel || isSmRejectingCancel)
                ? () {}
                : () async {
                    setState(() => _activeActionKeys.add(smRejectCancelKey));
                    try {
                      await _handleStrangersMeetCancellationAction(
                        meetId,
                        cId,
                        'reject',
                      );
                    } finally {
                      if (mounted) {
                        setState(
                          () => _activeActionKeys.remove(smRejectCancelKey),
                        );
                      }
                    }
                  },
          ),
        ];
      } else if (pendingIncomingRequests.isNotEmpty) {
        final int confirmedCount =
            int.tryParse(
              (meetMap['paidJoinersCount'] ??
                      meetMap['slotsFilled'] ??
                      meetMap['confirmedCount'] ??
                      meetMap['paymentCount'] ??
                      0)
                  .toString(),
            ) ??
            0;
        final int totalCapacity =
            int.tryParse(
              (meetMap['numberOfPersons'] ?? meetMap['capacity'] ?? 0)
                  .toString(),
            ) ??
            0;
        final int pendingCount = pendingIncomingRequests.length;
        final countSubtitle = totalCapacity > 0
            ? ' • $confirmedCount/$totalCapacity Confirmed'
            : (confirmedCount > 0 ? ' • $confirmedCount Confirmed' : '');

        if (pendingIncomingRequests.length == 1) {
          final firstReq = pendingIncomingRequests.first;
          final reqUser = (firstReq['requester'] is Map)
              ? firstReq['requester'] as Map<String, dynamic>
              : <String, dynamic>{};
          final reqUserName =
              '${reqUser["firstName"] ?? "A user"} ${reqUser["lastName"] ?? ""}'
                  .trim();
          final joinerId = firstReq['id']?.toString() ?? '';

          title = '📥 Join Request Received';
          badge = 'NEW REQUEST';
          body =
              '$reqUserName requested to join your Stranger Meet at $venueName.$countSubtitle';
          senderUser = reqUser.isNotEmpty ? reqUser : hostCreator;
          avatarUrl = reqUser['profileImageUrl'] ?? reqUser['profilePhotoUrl'];

          partnerUser = reqUser.isNotEmpty ? reqUser : null;
          partnerRoleLabel = 'Request from:';
          statusSummary = totalCapacity > 0
              ? '1 Pending • $confirmedCount/$totalCapacity Confirmed'
              : '1 Pending • $confirmedCount Confirmed';

          final isAcceptingSm = _activeActionKeys.contains(
            'sm_join_accept_$joinerId',
          );
          final isDecliningSm = _activeActionKeys.contains(
            'sm_join_reject_$joinerId',
          );
          actionsList = [
            NotificationAction(
              label: isAcceptingSm ? 'Accepting...' : 'Accept',
              icon: Icons.check_circle_rounded,
              isPrimary: true,
              isLoading: isAcceptingSm,
              onTap: (isAcceptingSm || isDecliningSm)
                  ? () {}
                  : () => _handleStrangersMeetJoinAction(
                      meetId,
                      joinerId,
                      'accept',
                    ),
            ),
            NotificationAction(
              label: isDecliningSm ? 'Declining...' : 'Decline',
              icon: Icons.cancel_rounded,
              isPrimary: false,
              isLoading: isDecliningSm,
              color: Colors.grey[200],
              onTap: (isAcceptingSm || isDecliningSm)
                  ? () {}
                  : () => _handleStrangersMeetJoinAction(
                      meetId,
                      joinerId,
                      'reject',
                    ),
            ),
          ];
        } else {
          title = '📥 Join Requests Received';
          badge = 'REQUESTS ($pendingCount)';
          body =
              '$pendingCount users requested to join your Stranger Meet at $venueName.$countSubtitle';
          statusSummary = totalCapacity > 0
              ? '$pendingCount Pending • $confirmedCount/$totalCapacity Confirmed'
              : '$pendingCount Pending • $confirmedCount Confirmed';
          actionsList = [
            NotificationAction(
              label: 'Review Requests ($pendingCount)',
              icon: Icons.people_alt_rounded,
              isPrimary: true,
              onTap: () => _showReviewStrangersMeetRequestsModal(
                meetMap,
                pendingIncomingRequests,
              ),
            ),
          ];
        }
      } else if (paidJoinerRecord != null) {
        final joiner = (paidJoinerRecord['requester'] is Map)
            ? paidJoinerRecord['requester'] as Map<String, dynamic>
            : <String, dynamic>{};
        final joinerName =
            '${joiner["firstName"] ?? "Participant"} ${joiner["lastName"] ?? ""}'
                .trim();
        final joinerId = joiner['id']?.toString() ?? '';
        final joinerPhoto =
            joiner['profileImageUrl']?.toString() ??
            joiner['profilePhotoUrl']?.toString();

        title = '🎉 Seat Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body =
            'Your Stranger Meet with $joinerName at $venueName is locked! Chat unlocked.';
        senderUser = joiner.isNotEmpty ? joiner : hostCreator;
        avatarUrl = joinerPhoto ?? hostPhoto;

        partnerUser = joiner.isNotEmpty ? joiner : null;
        partnerRoleLabel = 'Participant:';
        statusSummary = 'Payment Done • Chat Unlocked';

        actionsList = [
          if (meetMap['startedAt'] == null)
            NotificationAction(
              label: 'Start Meetup',
              icon: Icons.play_circle_fill_rounded,
              isPrimary: true,
              onTap: () {
                StrangersMeetStartDialog.show(
                  context,
                  meetId: meetId,
                  subject: meetMap['subject']?.toString() ?? 'Strangers Meet',
                  venueName: venueName,
                  eventDateTime: parsedEventDate ?? DateTime.now(),
                  onStarted: () => _loadFeed(),
                );
              },
            ),
          NotificationAction(
            label: 'Chat',
            icon: Icons.chat_bubble_rounded,
            isPrimary: meetMap['startedAt'] != null,
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
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
        statusSummary = 'Live & Open';
        actionsList = [
          if (meetMap['startedAt'] == null)
            NotificationAction(
              label: 'Start Meetup',
              icon: Icons.play_circle_fill_rounded,
              isPrimary: true,
              onTap: () {
                StrangersMeetStartDialog.show(
                  context,
                  meetId: meetId,
                  subject: meetMap['subject']?.toString() ?? 'Strangers Meet',
                  venueName: venueName,
                  eventDateTime: parsedEventDate ?? DateTime.now(),
                  onStarted: () => _loadFeed(),
                );
              },
            ),
          NotificationAction(
            label: 'View Ticket',
            icon: Icons.confirmation_number_rounded,
            isPrimary: meetMap['startedAt'] != null,
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
          NotificationAction(
            label: 'Cancel',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              final int actualPaidCount =
                  int.tryParse(
                    (meetMap['paidJoinersCount'] ??
                            meetMap['slotsFilled'] ??
                            meetMap['joinedCount'] ??
                            0)
                        .toString(),
                  ) ??
                  0;
              final double totalCollected = actualPaidCount * chargesPerHead;
              final int totalCapacity =
                  int.tryParse(
                    (meetMap['numberOfPersons'] ?? meetMap['capacity'] ?? 0)
                        .toString(),
                  ) ??
                  0;
              final double hostDeposit =
                  double.tryParse((meetMap['paymentAmount'] ?? 0).toString()) ??
                  0.0;
              final String meetDate = parsedEventDate != null
                  ? DateFormat('MMM dd, yyyy').format(parsedEventDate)
                  : '';
              final String meetTime = parsedEventDate != null
                  ? DateFormat('hh:mm a').format(parsedEventDate)
                  : '';

              StrangersMeetHostCancellationDialog.show(
                context,
                meetId: meetId,
                subject:
                    meetMap['subject']?.toString() ??
                    meetMap['title']?.toString() ??
                    'Strangers Meet',
                venueName: venueName,
                joinedCount: actualPaidCount,
                collectedAmount: totalCollected,
                date: meetDate,
                time: meetTime,
                totalCapacity: totalCapacity > 0 ? totalCapacity : null,
                paidCount: actualPaidCount,
                hostDeposit: hostDeposit,
                onCancelled: () => _loadFeed(),
              );
            },
          ),
        ];
      }
    } else {
      userRoleLabel = 'Hosted by';
      partnerUser = hostCreator.isNotEmpty ? hostCreator : null;
      partnerRoleLabel = 'Host:';

      final myStatus = (myRequest?['status'] ?? '').toString().toLowerCase();
      final myPaymentStatus =
          (myRequest?['joinerPaymentStatus'] ??
                  myRequest?['paymentStatus'] ??
                  '')
              .toString()
              .toLowerCase();
      final myCancel = meetMap['myCancellation'] is Map
          ? Map<String, dynamic>.from(meetMap['myCancellation'])
          : null;
      final hostCancellation = meetMap['hostCancellation'] is Map
          ? Map<String, dynamic>.from(meetMap['hostCancellation'])
          : null;

      if (hostCancellation != null &&
          hostCancellation['status'] == 'PENDING_ADMIN_REVIEW') {
        title = '⏳ Host Cancellation Pending';
        badge = 'HOST CANCELLATION';
        accent = const Color(0xFFF59E0B);
        body =
            'The host has requested cancellation for this Stranger Meet. Lunara Admin is currently reviewing the request.';
        statusSummary = 'Admin Review In Progress';
        actionsList = [
          NotificationAction(
            label: 'View Ticket',
            icon: Icons.confirmation_number_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
        ];
      } else if (meetStatus == 'cancelled' ||
          (hostCancellation != null &&
              (hostCancellation['status'] == 'COMPLETED' ||
                  hostCancellation['status'] == 'REFUNDED' ||
                  hostCancellation['status'] == 'APPROVED' ||
                  hostCancellation['status'] == 'REFUND_PROCESSING'))) {
        final refAmount = (myRequest?['paymentAmount'] ?? chargesPerHead);
        title = '🎉 Strangers Meet Cancelled';
        badge = 'REFUND PROCESSED';
        accent = const Color(0xFF10B981);
        body =
            'The Strangers Meet at $venueName was cancelled by the host. Your payment of ₹$refAmount has been refunded to your Lunara Wallet.';
        statusSummary = 'Refund Processed';
        actionsList = [
          NotificationAction(
            label: 'View Details',
            icon: Icons.info_outline_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
          NotificationAction(
            label: 'View Wallet',
            icon: Icons.account_balance_wallet_rounded,
            isPrimary: true,
            onTap: () => Navigator.pushNamed(context, '/wallet'),
          ),
        ];
      } else if (myCancel != null && myCancel['status'] == 'pending') {
        title = '⏳ Cancellation Requested';
        badge = 'CANCELLATION PENDING';
        accent = const Color(0xFFF59E0B);
        body =
            'Your cancellation request for Stranger Meet at $venueName is awaiting host approval.';
        statusSummary = 'Awaiting Host Approval';
        actionsList = [
          NotificationAction(
            label: 'View Ticket',
            icon: Icons.confirmation_number_rounded,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              try {
                final req = StrangersMeetRequest.fromJson(meetMap);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
        ];
      } else if (myCancel != null && myCancel['status'] == 'approved') {
        final ref = myCancel['refundAmount'] ?? myCancel['paidAmount'] ?? 0;
        title = '✓ Cancellation Approved';
        badge = 'REFUNDED';
        accent = const Color(0xFF10B981);
        body =
            'Your cancellation was approved by $hostName. ₹$ref has been refunded to your Lunara Wallet.';
        statusSummary = '₹$ref Refunded to Wallet';
        actionsList = [
          NotificationAction(
            label: 'View Wallet',
            icon: Icons.account_balance_wallet_rounded,
            isPrimary: true,
            onTap: () => Navigator.pushNamed(context, '/wallet'),
          ),
        ];
      } else if (myStatus == 'paid' || myPaymentStatus == 'paid') {
        title = '🎉 Meet Confirmed!';
        badge = 'CONFIRMED';
        accent = const Color(0xFF10B981);
        body =
            'Your Stranger Meet with $hostName at $venueName is confirmed! Chat unlocked.';
        final otherId = meetHostId.isNotEmpty
            ? meetHostId
            : (hostCreator['id'] ?? '');
        statusSummary = 'Payment Done • Chat Unlocked';

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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(request: req),
                  ),
                );
              } catch (e) {
                debugPrint('Error parsing SM ticket: $e');
              }
            },
          ),
          NotificationAction(
            label: 'Cancel',
            icon: Icons.cancel_outlined,
            isPrimary: false,
            color: Colors.grey[200],
            onTap: () {
              if (isHost) {
                final int actualPaidCount =
                    int.tryParse(
                      (meetMap['paidJoinersCount'] ??
                              meetMap['slotsFilled'] ??
                              meetMap['joinedCount'] ??
                              0)
                          .toString(),
                    ) ??
                    0;
                final double totalCollected = actualPaidCount * chargesPerHead;
                final int totalCapacity =
                    int.tryParse(
                      (meetMap['numberOfPersons'] ?? meetMap['capacity'] ?? 0)
                          .toString(),
                    ) ??
                    0;
                final double hostDeposit =
                    double.tryParse(
                      (meetMap['paymentAmount'] ?? 0).toString(),
                    ) ??
                    0.0;
                final String meetDate = parsedEventDate != null
                    ? DateFormat('MMM dd, yyyy').format(parsedEventDate)
                    : '';
                final String meetTime = parsedEventDate != null
                    ? DateFormat('hh:mm a').format(parsedEventDate)
                    : '';

                StrangersMeetHostCancellationDialog.show(
                  context,
                  meetId: meetId,
                  subject:
                      meetMap['subject']?.toString() ??
                      meetMap['title']?.toString() ??
                      'Strangers Meet',
                  venueName: venueName,
                  joinedCount: actualPaidCount,
                  collectedAmount: totalCollected,
                  date: meetDate,
                  time: meetTime,
                  totalCapacity: totalCapacity > 0 ? totalCapacity : null,
                  paidCount: actualPaidCount,
                  hostDeposit: hostDeposit,
                  onCancelled: () => _loadFeed(),
                );
              } else {
                final double paid =
                    (chargesPerHead > 0
                            ? chargesPerHead
                            : double.tryParse(
                                    (meetMap['paymentAmount'] ?? '0')
                                        .toString(),
                                  ) ??
                                  0.0)
                        .toDouble();
                StrangersMeetCancellationDialog.show(
                  context,
                  meetId: meetId,
                  subject: meetMap['subject']?.toString() ?? 'Strangers Meet',
                  venueName: venueName,
                  paidAmount: paid,
                  onCancelled: () => _loadFeed(),
                );
              }
            },
          ),
        ];
      } else if (myStatus == 'accepted' || myStatus == 'payment_pending') {
        final feeLabel = chargesPerHead > 0
            ? '₹${chargesPerHead.toStringAsFixed(0)}'
            : 'Entry Fee';
        title = '✅ Accepted! Pay Entry Fee';
        badge = 'ACTION REQUIRED';
        accent = const Color(0xFFF59E0B);
        body =
            '$hostName accepted your request! Pay $feeLabel to secure your spot at $venueName.';
        statusSummary = 'Pay $feeLabel';

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
        body =
            'Request sent to $hostName for Stranger Meet at $venueName. Waiting for host approval.';
        statusSummary = 'Pending Approval';
        actionsList = null;
      } else if (myStatus == 'rejected' || myStatus == 'declined') {
        title = '❌ Request Declined';
        badge = 'DECLINED';
        accent = const Color(0xFF9CA3AF);
        body =
            'Your request to join Stranger Meet at $venueName was declined by $hostName.';
        statusSummary = 'Declined';
        actionsList = null;
      } else {
        final double charges = (meetMap['chargesPerHead'] is num
            ? (meetMap['chargesPerHead'] as num).toDouble()
            : (double.tryParse((meetMap['chargesPerHead'] ?? '0').toString()) ??
                  0.0));
        final feeLabel = charges > 0 ? ' (₹${charges.toStringAsFixed(0)})' : '';

        title = '🤝 Stranger Meet at $venueName';
        badge = 'STRANGER MEET';
        body = formattedDateTime.isNotEmpty
            ? '$hostName is hosting • $formattedDateTime'
            : '$hostName is hosting a Stranger Meet at $venueName.';

        if (hostPayStatus == 'paid' ||
            meetStatus == 'confirmed' ||
            meetStatus == 'live') {
          actionsList = [
            NotificationAction(
              label: 'Request to Join$feeLabel',
              icon: Icons.person_add_rounded,
              isPrimary: true,
              onTap: () {
                try {
                  final Map<String, dynamic> postMap =
                      Map<String, dynamic>.from(meetMap);
                  postMap['type'] = 'strangers_meet';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostDetailScreen(post: postMap),
                    ),
                  );
                } catch (e) {
                  debugPrint(
                    'Error navigating to SM detail from live card: $e',
                  );
                }
              },
            ),
          ];
        } else {
          statusSummary = 'Waiting for Host Deposit';
          actionsList = null;
        }
      }
    }

    DateTime latestCreatedAt = DateTime(2000);
    bool allRead = true;
    for (final e in entries) {
      final dt = _parseDateTime(
        e['lastActivityAt'] ??
            e['updatedAt'] ??
            e['createdAt'] ??
            e['postedAt'],
      );
      if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
      final eId = e['id']?.toString() ?? '';
      final read =
          e['read'] == true ||
          e['isRead'] == true ||
          _localReadNotificationIds.contains(eId) ||
          ApiService.localReadRequestIds.contains(eId);
      if (!read) allRead = false;
    }
    if (meetMap['lastActivityAt'] != null) {
      try {
        final dt = _parseDateTime(meetMap['lastActivityAt']);
        if (dt.isAfter(latestCreatedAt)) latestCreatedAt = dt;
      } catch (_) {}
    }
    if (_localReadNotificationIds.contains('sm_$meetId') ||
        _localReadNotificationIds.contains(meetId) ||
        ApiService.localReadRequestIds.contains('sm_$meetId') ||
        ApiService.localReadRequestIds.contains(meetId)) {
      allRead = true;
    }
    if (badge == 'ACTION REQUIRED' ||
        badge == 'NEW REQUEST' ||
        badge == 'INVITE') {
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
      rawData: {
        'id': meetId,
        'plan': meetMap,
        'pendingIncomingRequests': pendingIncomingRequests,
        ...meetMap,
      },
      userRoleLabel: userRoleLabel,
      partnerUser: partnerUser,
      partnerRoleLabel: partnerRoleLabel,
      statusSummary: statusSummary,
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
          {
            'id': 'ALL',
            'label': 'All Notifications',
            'icon': Icons.notifications_rounded,
          },
          {
            'id': 'BOOKINGS',
            'label': 'Bookings & Invites',
            'icon': Icons.confirmation_number_rounded,
          },
          {
            'id': 'PARTY_PLANS',
            'label': 'Party Plans',
            'icon': Icons.celebration_rounded,
          },
          {
            'id': 'STRANGER_MEETS',
            'label': 'Stranger Meets',
            'icon': Icons.people_alt_rounded,
          },
          {
            'id': 'PAYMENTS',
            'label': 'Payments & Receipts',
            'icon': Icons.payments_rounded,
          },
          {
            'id': 'WALLET',
            'label': 'Wallet Balance',
            'icon': Icons.account_balance_wallet_rounded,
          },
          {
            'id': 'CHAT',
            'label': 'Messages & Chat',
            'icon': Icons.chat_bubble_rounded,
          },
          {
            'id': 'EXPIRED',
            'label': 'Expired Plans & Events',
            'icon': Icons.history_rounded,
          },
          {
            'id': 'SYSTEM',
            'label': 'System & Security',
            'icon': Icons.security_rounded,
          },
          {
            'id': 'PROMOTIONS',
            'label': 'Offers & Rewards',
            'icon': Icons.card_giftcard_rounded,
          },
        ];

        return StatefulBuilder(
          builder: (ctx, setBottomSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
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
                              style: TextStyle(
                                color: LunaraTheme.electricViolet,
                                fontWeight: FontWeight.bold,
                              ),
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
                          final isSelected =
                              _selectedCategoryFilter == filterId;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            leading: Icon(
                              filter['icon'] as IconData,
                              color: isSelected
                                  ? LunaraTheme.electricViolet
                                  : Colors.grey[600],
                            ),
                            title: Text(
                              filter['label'] as String,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? LunaraTheme.electricViolet
                                    : Colors.black87,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: LunaraTheme.electricViolet,
                                    size: 20,
                                  )
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
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: LunaraTheme.electricViolet,
                      size: 24,
                    ),
                    if (totalUnread > 0)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            totalUnread > 9 ? '9+' : '$totalUnread',
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
                icon: const Icon(
                  Icons.done_all_rounded,
                  size: 15,
                  color: LunaraTheme.electricViolet,
                ),
                label: const Text(
                  'Read All',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: LunaraTheme.electricViolet,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
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
                    color: _selectedCategoryFilter != 'ALL'
                        ? LunaraTheme.electricViolet.withValues(alpha: 0.1)
                        : Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: _selectedCategoryFilter != 'ALL'
                        ? LunaraTheme.electricViolet
                        : Colors.black87,
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
    if (pillId == 'ALL') {
      return allItems.where((i) {
        if (i.isRead || i.isExpired) return false;
        final category = i.category.toLowerCase();
        final title = i.title.toLowerCase();
        final badge = i.badgeText?.toUpperCase() ?? '';
        final isSystem = category == 'system' ||
            category == 'promotion' ||
            category == 'promo' ||
            badge.contains('SYSTEM') ||
            badge.contains('PROMO') ||
            title.contains('vip plan') ||
            title.contains('super likes usage');
        return !isSystem;
      }).length;
    }
    if (pillId == 'EXPIRED') {
      return allItems.where((i) => i.isExpired && !i.isRead).length;
    }
    return allItems.where((item) {
      if (item.isExpired) return false;
      final badge = item.badgeText?.toUpperCase() ?? '';
      final category = item.category.toLowerCase();
      final title = item.title.toLowerCase();
      final isSystem = category == 'system' ||
          category == 'promotion' ||
          category == 'promo' ||
          badge.contains('SYSTEM') ||
          badge.contains('PROMO') ||
          title.contains('vip plan') ||
          title.contains('super likes usage');

      final rawStatus =
          (item.rawData['status'] ??
                  item.rawData['paymentStatus'] ??
                  item.rawData['stage'] ??
                  '')
              .toString()
              .toLowerCase();
      final cancellationStatus = (item.rawData['cancellationStatus'] ?? '')
          .toString()
          .toLowerCase();
      bool matches = false;
      if (pillId == 'REQUESTS') {
        matches = !isSystem && (
            title.contains('request') ||
            title.contains('invite') ||
            title.contains('partner') ||
            badge.contains('REQUEST') ||
            badge.contains('INVITE') ||
            category.contains('request') ||
            category.contains('upcoming_night') ||
            category.contains('night_partner'));
      } else if (pillId == 'PENDING') {
        matches = !isSystem && (
            rawStatus.contains('pending') ||
            rawStatus.contains('invite_sent') ||
            rawStatus.contains('waiting_for_payment') ||
            rawStatus.contains('requested') ||
            cancellationStatus.contains('requested') ||
            badge.contains('ACTION REQUIRED') ||
            badge.contains('PENDING') ||
            badge.contains('INVITE') ||
            badge.contains('WAITING'));
      } else if (pillId == 'PAYMENT') {
        matches =
            category.contains('pay') ||
            category.contains('wallet') ||
            category.contains('deposit') ||
            rawStatus.contains('pay') ||
            rawStatus.contains('waiting_for_payment') ||
            badge.contains('PAYMENT') ||
            badge.contains('ACTION REQUIRED') ||
            title.contains('payment') ||
            title.contains('paid');
      } else if (pillId == 'CONFIRMED') {
        matches =
            rawStatus.contains('confirmed') ||
            rawStatus.contains('paid') ||
            badge.contains('CONFIRMED') ||
            title.contains('confirmed');
      } else if (pillId == 'SYSTEM') {
        matches = isSystem;
      }
      return matches && !item.isRead;
    }).length;
  }

  Widget _buildStatusFilterBar() {
    final allTimelineItems = _cachedTimeline.isNotEmpty
        ? _cachedTimeline
        : _buildUnifiedTimeline();
    final pills = [
      {'id': 'ALL', 'label': 'All'},
      {'id': 'REQUESTS', 'label': 'Requests'},
      {'id': 'PENDING', 'label': 'Pending'},
      {'id': 'PAYMENT', 'label': 'Payment'},
      {'id': 'CONFIRMED', 'label': 'Confirmed'},
      {'id': 'EXPIRED', 'label': 'Expired'},
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: isSelected
                                ? LunaraTheme.electricViolet
                                : Colors.white,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
    final allTimelineItems = _cachedTimeline.isNotEmpty
        ? _cachedTimeline
        : _buildUnifiedTimeline();

    // Apply category filter
    final categoryFilteredItems = allTimelineItems.where((item) {
      if (_selectedCategoryFilter == 'ALL') return true;
      if (_selectedCategoryFilter == 'EXPIRED') {
        return item.isExpired;
      }
      if (_selectedCategoryFilter == 'BOOKINGS') {
        return item.category == 'booking' ||
            item.category == 'group' ||
            item.category == 'upcoming_night' ||
            item.category == 'night_partner';
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

    // Apply status pill filter (All, Requests, Pending, Payment, Confirmed, Expired, System)
    final filteredItems = categoryFilteredItems.where((item) {
      if (_selectedStatusPill == 'EXPIRED' ||
          _selectedCategoryFilter == 'EXPIRED') {
        return item.isExpired;
      }

      // Expired items must NOT show in 'ALL' or other active tabs
      if (item.isExpired) {
        return false;
      }

      final badge = item.badgeText?.toUpperCase() ?? '';
      final category = item.category.toLowerCase();
      final title = item.title.toLowerCase();
      final body = item.body.toLowerCase();
      final isSystemNotif = category.contains('system') ||
          category.contains('promo') ||
          category.contains('promotion') ||
          badge.contains('SYSTEM') ||
          badge.contains('PROMO') ||
          title.contains('vip plan') ||
          title.contains('super likes usage') ||
          body.contains('subscription will expire') ||
          body.contains('super likes');

      if (_selectedStatusPill == 'ALL') {
        // Exclude system notifications from ALL tab so they only appear in SYSTEM
        return !isSystemNotif;
      }

      final rawStatus =
          (item.rawData['status'] ??
                  item.rawData['paymentStatus'] ??
                  item.rawData['stage'] ??
                  '')
              .toString()
              .toLowerCase();
      final cancellationStatus = (item.rawData['cancellationStatus'] ?? '')
          .toString()
          .toLowerCase();

      if (_selectedStatusPill == 'REQUESTS') {
        return !isSystemNotif && (
            title.contains('request') ||
            title.contains('invite') ||
            title.contains('partner') ||
            body.contains('request') ||
            body.contains('invite') ||
            body.contains('partner') ||
            badge.contains('REQUEST') ||
            badge.contains('INVITE') ||
            category.contains('request') ||
            category.contains('upcoming_night') ||
            category.contains('night_partner')
        );
      }
      if (_selectedStatusPill == 'PENDING') {
        return !isSystemNotif && (
            rawStatus.contains('pending') ||
            rawStatus.contains('invite_sent') ||
            rawStatus.contains('waiting_for_payment') ||
            rawStatus.contains('requested') ||
            cancellationStatus.contains('requested') ||
            badge.contains('ACTION REQUIRED') ||
            badge.contains('PENDING') ||
            badge.contains('INVITE') ||
            badge.contains('WAITING')
        );
      }
      if (_selectedStatusPill == 'PAYMENT') {
        final hasPayAction =
            item.actions?.any(
              (act) => act.label.toLowerCase().contains('pay'),
            ) ??
            false;
        return category.contains('pay') ||
            category.contains('wallet') ||
            category.contains('deposit') ||
            rawStatus.contains('pay') ||
            rawStatus.contains('deposit') ||
            rawStatus.contains('waiting_for_payment') ||
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
        return rawStatus.contains('confirmed') ||
            rawStatus.contains('paid') ||
            badge.contains('CONFIRMED') ||
            title.contains('confirmed');
      }
      if (_selectedStatusPill == 'SYSTEM') {
        return isSystemNotif;
      }
      return true;
    }).toList();

    // Count total unread active items
    final totalUnread = allTimelineItems
        .where((i) => !i.isRead && !i.isExpired)
        .length;

    // Date grouping into TODAY, YESTERDAY, EARLIER
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final todayItems = filteredItems
        .where((i) => i.createdAt.isAfter(todayStart))
        .toList();
    final yesterdayItems = filteredItems
        .where(
          (i) =>
              i.createdAt.isAfter(yesterdayStart) &&
              i.createdAt.isBefore(todayStart),
        )
        .toList();
    final earlierItems = filteredItems
        .where((i) => i.createdAt.isBefore(yesterdayStart))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, totalUnread: totalUnread),
            _buildStatusFilterBar(),
            Expanded(
              child: _isLoading && filteredItems.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.electricViolet,
                      ),
                    )
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
                                      Icon(
                                        Icons.notifications_none_rounded,
                                        size: 64,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _selectedStatusPill == 'EXPIRED' ||
                                                _selectedCategoryFilter ==
                                                    'EXPIRED'
                                            ? 'No expired plans or notifications'
                                            : _selectedCategoryFilter != 'ALL'
                                            ? 'No notifications in this category'
                                            : _selectedStatusPill != 'ALL'
                                            ? 'No $_selectedStatusPill notifications'
                                            : 'No notifications yet',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Your timeline updates will appear here dynamically',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (todayItems.isNotEmpty) ...[
                                  _buildDateSectionHeader('TODAY'),
                                  ...todayItems.map(
                                    (item) => _buildSmartNotificationCard(item),
                                  ),
                                ],
                                if (yesterdayItems.isNotEmpty) ...[
                                  _buildDateSectionHeader('YESTERDAY'),
                                  ...yesterdayItems.map(
                                    (item) => _buildSmartNotificationCard(item),
                                  ),
                                ],
                                if (earlierItems.isNotEmpty) ...[
                                  _buildDateSectionHeader('EARLIER'),
                                  ...earlierItems.map(
                                    (item) => _buildSmartNotificationCard(item),
                                  ),
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
          color: item.isRead
              ? Colors.grey[200]!
              : LunaraTheme.electricViolet.withValues(alpha: 0.3),
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
                  decoration: BoxDecoration(color: item.accentColor),
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
                            if (item.senderUser != null ||
                                (item.avatarUrl != null &&
                                    item.avatarUrl!.isNotEmpty))
                              Builder(
                                builder: (_) {
                                  final String? resolvedPhoto =
                                      item.senderUser?['profilePhotoUrl']
                                          ?.toString() ??
                                      item.senderUser?['profileImageUrl']
                                          ?.toString() ??
                                      item.senderUser?['photoUrl']
                                          ?.toString() ??
                                      item.senderUser?['profilePhoto']
                                          ?.toString() ??
                                      item.avatarUrl;

                                  final Map<String, dynamic> userMap =
                                      Map<String, dynamic>.from(
                                        item.senderUser ?? {},
                                      );
                                  if (resolvedPhoto != null &&
                                      resolvedPhoto.isNotEmpty &&
                                      resolvedPhoto != 'null') {
                                    userMap['profilePhotoUrl'] = resolvedPhoto;
                                    userMap['profileImageUrl'] = resolvedPhoto;
                                    userMap['photoUrl'] = resolvedPhoto;
                                    userMap['profilePhoto'] = resolvedPhoto;
                                    userMap['photos'] = [
                                      {
                                        'url': resolvedPhoto,
                                        'filePath': resolvedPhoto,
                                        'isPrimary': true,
                                      },
                                    ];
                                  }

                                  return LunaraProfileImage(
                                    userData: userMap.isNotEmpty
                                        ? userMap
                                        : {
                                            'profilePhotoUrl': resolvedPhoto,
                                            'profileImageUrl': resolvedPhoto,
                                            'firstName': item.title,
                                          },
                                    radius: 18,
                                    isInteractive:
                                        item.senderUser != null &&
                                        item.senderUser!['id'] != null,
                                  );
                                },
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: item.accentColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  item.categoryIcon,
                                  size: 18,
                                  color: item.accentColor,
                                ),
                              ),
                            const SizedBox(width: 10),

                            // Badge Tag
                            if (item.badgeText != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
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

                        // Title / Activity Headline
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),

                        // ── Role & Participant Info Box ──
                        if (item.partnerUser != null ||
                            item.userRoleLabel != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (item.partnerUser != null) ...[
                                  LunaraProfileImage(
                                    userData: item.partnerUser!,
                                    radius: 15,
                                    isInteractive:
                                        item.partnerUser!['id'] != null,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (item.userRoleLabel != null)
                                        Text(
                                          item.userRoleLabel!,
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF64748B),
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      if (item.partnerUser != null)
                                        Text(
                                          '${item.partnerRoleLabel ?? "With:"} ${item.partnerUser!["firstName"] ?? item.partnerUser!["name"] ?? "User"} ${item.partnerUser!["lastName"] ?? ""}'
                                              .trim(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (item.statusSummary != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEDE9FE),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.statusSummary!,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 6),

                        // Body Description
                        Text(
                          item.body,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            height: 1.3,
                          ),
                          maxLines:
                              (item.category == 'party_plan' ||
                                  item.body.contains('\n'))
                              ? 6
                              : 3,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Expired notice
                        if (item.badgeText == 'EXPIRED') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: const [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: Colors.grey,
                              ),
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

                        // Action Buttons Wrap (Accept/Decline/Pay/View Ticket/Chat)
                        if (item.actions != null &&
                            item.actions!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: item.actions!.map((action) {
                                final isPrimary = action.isPrimary;
                                final btnColor =
                                    action.color ??
                                    (isPrimary
                                        ? item.accentColor
                                        : Colors.grey[200]!);
                                final textColor = isPrimary
                                    ? Colors.white
                                    : Colors.black87;
                                final isLoading = action.isLoading;

                                return ElevatedButton.icon(
                                  onPressed: isLoading ? null : action.onTap,
                                  icon: isLoading
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  isPrimary
                                                      ? Colors.white
                                                      : LunaraTheme
                                                            .electricViolet,
                                                ),
                                          ),
                                        )
                                      : (action.icon != null
                                            ? Icon(
                                                action.icon,
                                                size: 15,
                                                color: textColor,
                                              )
                                            : const SizedBox.shrink()),
                                  label: Text(
                                    action.label,
                                    style: TextStyle(
                                      color: isLoading
                                          ? textColor.withValues(alpha: 0.6)
                                          : textColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: btnColor,
                                    foregroundColor: textColor,
                                    disabledBackgroundColor: btnColor
                                        .withValues(alpha: 0.7),
                                    disabledForegroundColor: textColor
                                        .withValues(alpha: 0.7),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    minimumSize: const Size(80, 40),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: !isPrimary
                                          ? BorderSide(
                                              color: Colors.grey[300]!,
                                              width: 0.8,
                                            )
                                          : BorderSide.none,
                                    ),
                                  ),
                                );
                              }).toList(),
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

    final bool? sheetSuccess = await SmartCheckoutSheet.show(
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
          final transactionId =
              res['data']?['transactionId']?.toString() ?? 'wallet';
          final paymentConfirmed = await ApiService.verifyHostPayment(
            cleanPlanId,
            'order_mock_wallet',
            'wallet_$transactionId',
            'mock_signature',
          );
          if (paymentConfirmed) {
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

    if (sheetSuccess == true && mounted) {
      TopNotificationBanner.show(
        title: 'Plan Activated! 🎉',
        body:
            'Host Safety Deposit paid via Smart Wallet! Your plan is now LIVE in the feed.',
      );
      ApiService.clearBookingCache();
      ApiService.notifyFeedNeedsRefresh();
      await onSuccess();
      _loadFeed(showLoader: false, forceRefresh: true);
    }
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
      if (initRes['razorpayKeyId'] != null &&
          initRes['razorpayKeyId'].toString().isNotEmpty) {
        razorpayKey = initRes['razorpayKeyId'].toString();
      }
    }

    if (currentOrderId.isEmpty) {
      currentOrderId = 'order_mock_${DateTime.now().millisecondsSinceEpoch}';
    }

    // Intercept mock orders or test keys to avoid Razorpay SDK code 0 error on devices
    if (currentOrderId.startsWith('order_mock_') ||
        razorpayKey == 'rzp_test_123' ||
        currentOrderId.startsWith('mock_')) {
      final paymentConfirmed = await ApiService.verifyHostPayment(
        cleanPlanId,
        currentOrderId,
        'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        'mock_signature',
      );
      if (paymentConfirmed && mounted) {
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        await onSuccess();
        _loadFeed(showLoader: false, forceRefresh: true);
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

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
      PaymentSuccessResponse response,
    ) async {
      final pId =
          response.paymentId ??
          'pay_mock_${DateTime.now().millisecondsSinceEpoch}';
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
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        await onSuccess();
        _loadFeed(showLoader: false, forceRefresh: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 Host Safety Deposit Paid! Your plan is fully activated.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        // Never treat a client-side/mock identifier as confirmation. The
        // backend verification result is the only payment success signal.
        if (!paymentConfirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment verification failed. Please refresh and try again.',
              ),
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
          const msg =
              'Payment verification failed. Please refresh and try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $msg'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (
      PaymentFailureResponse response,
    ) async {
      razorpay.clear();
      debugPrint(
        '[PAYMENT-07] Razorpay error callback: code=${response.code}, message=${response.message}',
      );
      if (mounted) {
        if ((response.code == 0 || response.code == 2) &&
            (razorpayKey == 'rzp_test_123' ||
                currentOrderId.startsWith('order_mock_'))) {
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
                content: Text(
                  '🎉 Host Safety Deposit Paid! Plan is activated.',
                ),
                backgroundColor: Colors.green,
              ),
            );
            return;
          }
        }

        final isCancelled =
            response.code == Razorpay.PAYMENT_CANCELLED ||
            response.code == 2 ||
            response.code == 0 ||
            (response.message != null &&
                (response.message!.toLowerCase().contains('cancel') ||
                    response.message!.toLowerCase().contains('back') ||
                    response.message!.toLowerCase() == 'payment error' ||
                    response.message!.toLowerCase() == 'payment failed'));

        if (isCancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment cancelled. You can complete your deposit payment anytime.',
              ),
              backgroundColor: Colors.black87,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          final errText =
              response.message != null && response.message!.isNotEmpty
              ? response.message!
              : 'Payment error (code ${response.code})';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $errText'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (
      ExternalWalletResponse response,
    ) {
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

  void _optimisticallyUpdatePartyPlanPayment({
    required String planId,
    required bool isHost,
    String? requestId,
  }) {
    final cleanId = ApiService.cleanBookingId(planId);
    bool changed = false;

    // 1. Remove any stale pending_payment entries for this plan
    _feedItems.removeWhere((item) {
      final id = item['id']?.toString() ?? '';
      final pId = ApiService.cleanBookingId(
        (item['planId'] ?? item['partyPlanId'] ?? item['id'])?.toString() ??
            '',
      );
      if (id.startsWith('pending_pp_') ||
          item['type'] == 'pending_payment' ||
          item['requestType'] == 'party_plan_host_deposit') {
        if (pId == cleanId || pId == planId || id.contains(cleanId)) {
          changed = true;
          return true;
        }
      }
      return false;
    });

    for (int i = 0; i < _feedItems.length; i++) {
      final item = _feedItems[i];
      final rawId = ApiService.cleanBookingId(
        item['id']?.toString() ??
            item['partyPlanId']?.toString() ??
            item['planId']?.toString() ??
            item['plan']?['id']?.toString() ??
            '',
      );
      if (rawId == cleanId || rawId == planId) {
        final updated = Map<String, dynamic>.from(item);
        if (isHost) {
          updated['hostPaymentStatus'] = 'paid';
          updated['paymentStatus'] = 'paid';
          updated['isLive'] = true;
          updated['status'] = 'active';
          if (updated['plan'] is Map) {
            updated['plan'] = {
              ...Map<String, dynamic>.from(updated['plan'] as Map),
              'hostPaymentStatus': 'paid',
              'paymentStatus': 'paid',
              'isLive': true,
              'status': 'active',
            };
          }
        } else {
          updated['joinerPaymentStatus'] = 'paid';
          updated['paymentStatus'] = 'paid';
          updated['status'] = 'confirmed';
          updated['requestStatus'] = 'confirmed';
          if (updated['myRequest'] is Map) {
            updated['myRequest'] = {
              ...Map<String, dynamic>.from(updated['myRequest'] as Map),
              'status': 'confirmed',
              'joinerPaymentStatus': 'paid',
            };
          }
        }
        _feedItems[i] = updated;
        changed = true;
      }
    }

    if (changed) {
      _cachedTimeline = _buildUnifiedTimeline();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _optimisticallyUpdateStrangerMeetPayment({
    required String meetId,
    required bool isHost,
  }) {
    final cleanId = ApiService.cleanBookingId(meetId);
    bool changed = false;

    for (int i = 0; i < _feedItems.length; i++) {
      final item = _feedItems[i];
      final rawId = ApiService.cleanBookingId(
        item['id']?.toString() ??
            item['strangersMeetId']?.toString() ??
            item['meetId']?.toString() ??
            '',
      );
      if (rawId == cleanId || rawId == meetId) {
        final updated = Map<String, dynamic>.from(item);
        if (isHost) {
          updated['hostPaymentStatus'] = 'paid';
          updated['paymentStatus'] = 'paid';
          updated['status'] = 'approved';
        } else {
          updated['paymentStatus'] = 'paid';
          updated['status'] = 'confirmed';
          if (updated['myRequest'] is Map) {
            updated['myRequest'] = {
              ...Map<String, dynamic>.from(updated['myRequest'] as Map),
              'paymentStatus': 'paid',
              'status': 'confirmed',
            };
          }
        }
        _feedItems[i] = updated;
        changed = true;
      }
    }

    if (changed) {
      _cachedTimeline = _buildUnifiedTimeline();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _optimisticallyUpdateLargePartyPayment({required String bookingId}) {
    final cleanId = ApiService.cleanBookingId(bookingId);
    for (int i = 0; i < _largePartyBookings.length; i++) {
      final b = _largePartyBookings[i];
      final rawId = ApiService.cleanBookingId(
        b['id']?.toString() ?? b['bookingId']?.toString() ?? '',
      );
      if (rawId == cleanId || rawId == bookingId) {
        _largePartyBookings[i] = {
          ...b,
          'paymentStatus': 'paid',
          'status': 'confirmed',
        };
      }
    }
    _cachedTimeline = _buildUnifiedTimeline();
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic>? _findMyRequestForPlan(String planId) {
    final cleanId = ApiService.cleanBookingId(planId);
    for (final item in _feedItems) {
      final rawId = ApiService.cleanBookingId(
        item['id']?.toString() ??
            item['partyPlanId']?.toString() ??
            item['planId']?.toString() ??
            '',
      );
      if (rawId == cleanId || rawId == planId) {
        if (item['myRequest'] is Map) {
          return Map<String, dynamic>.from(item['myRequest'] as Map);
        }
        if (item['activeRequest'] is Map) {
          return Map<String, dynamic>.from(item['activeRequest'] as Map);
        }
        if (item['request'] is Map) {
          return Map<String, dynamic>.from(item['request'] as Map);
        }
        return item;
      }
    }
    return null;
  }

  Future<void> _startJoinerRazorpayDirectPaymentInLiveFeed({
    required String partyPlanId,
    required String requestId,
    required String venueName,
    required double depositAmount,
    required Future<void> Function() onSuccess,
  }) async {
    String cleanReqId = requestId.trim();
    if (cleanReqId.isEmpty) {
      final myReq = _findMyRequestForPlan(partyPlanId);
      cleanReqId = myReq?['id']?.toString() ?? '';
    }

    final double price = depositAmount > 0 ? depositAmount : 99.0;

    final bool? sheetSuccess = await SmartCheckoutSheet.show(
      context: context,
      title: 'Joiner Safety Deposit',
      subtitle: 'Confirm your match for Party Plan at $venueName',
      itemPrice: price,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: price,
          planId: partyPlanId,
          paymentType: 'joiner_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId =
              res['data']?['transactionId']?.toString() ?? 'wallet';
          final paymentConfirmed = await ApiService.verifyJoinerPayment(
            cleanReqId.isNotEmpty ? cleanReqId : partyPlanId,
            'order_mock_wallet',
            'wallet_$transactionId',
            'mock_signature',
          );
          if (paymentConfirmed) {
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
        await _launchRazorpayForJoinerPayment(
          cleanReqId: cleanReqId,
          partyPlanId: partyPlanId,
          venueName: venueName,
          depositAmount: price,
          onSuccess: onSuccess,
        );
      },
      onHybridPayment: (shortfall) async {
        await _launchRazorpayForJoinerPayment(
          cleanReqId: cleanReqId,
          partyPlanId: partyPlanId,
          venueName: venueName,
          depositAmount: shortfall > 0 ? shortfall : price,
          onSuccess: onSuccess,
        );
      },
    );

    if (sheetSuccess == true && mounted) {
      TopNotificationBanner.show(
        title: 'Match Confirmed! 🎉',
        body: 'Safety Deposit paid via Smart Wallet! Chat is now unlocked.',
      );
      ApiService.notifyFeedNeedsRefresh();
      await onSuccess();
      _loadFeed(showLoader: false);
    }
  }

  Future<void> _launchRazorpayForJoinerPayment({
    required String cleanReqId,
    required String partyPlanId,
    required String venueName,
    required double depositAmount,
    required Future<void> Function() onSuccess,
  }) async {
    final initRes = await ApiService.initiateJoinerPayment(
      cleanReqId.isNotEmpty ? cleanReqId : partyPlanId,
    );
    String currentOrderId = '';
    String razorpayKey = 'rzp_test_123';
    if (initRes != null && initRes['success'] == true) {
      currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
      if (initRes['razorpayKeyId'] != null &&
          initRes['razorpayKeyId'].toString().isNotEmpty) {
        razorpayKey = initRes['razorpayKeyId'].toString();
      }
    }

    if (currentOrderId.isEmpty) {
      currentOrderId = 'order_mock_${DateTime.now().millisecondsSinceEpoch}';
    }

    if (currentOrderId.startsWith('order_mock_') ||
        razorpayKey == 'rzp_test_123' ||
        currentOrderId.startsWith('mock_')) {
      final paymentConfirmed = await ApiService.verifyJoinerPayment(
        cleanReqId.isNotEmpty ? cleanReqId : partyPlanId,
        currentOrderId,
        'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        'mock_signature',
      );
      if (paymentConfirmed && mounted) {
        await onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 Safety Deposit Paid! Match confirmed & Chat unlocked.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }
    }

    late Razorpay razorpay;
    razorpay = Razorpay();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
      PaymentSuccessResponse response,
    ) async {
      final pId =
          response.paymentId ??
          'pay_mock_${DateTime.now().millisecondsSinceEpoch}';
      final oId = response.orderId ?? currentOrderId;
      final sig = response.signature ?? 'mock_signature';

      final paymentConfirmed = await ApiService.verifyJoinerPayment(
        cleanReqId.isNotEmpty ? cleanReqId : partyPlanId,
        oId,
        pId,
        sig,
      );

      razorpay.clear();
      if (paymentConfirmed && mounted) {
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        await onSuccess();
        _loadFeed(showLoader: false, forceRefresh: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 Safety Deposit Paid! Match confirmed & Chat unlocked.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        if (oId.startsWith('order_mock_') || pId.startsWith('pay_mock_')) {
          ApiService.clearBookingCache();
          ApiService.notifyFeedNeedsRefresh();
          await onSuccess();
          _loadFeed(showLoader: false, forceRefresh: true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Safety Deposit Paid! Match confirmed.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment verification failed. Please refresh and try again.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (
      PaymentFailureResponse response,
    ) async {
      razorpay.clear();
      debugPrint(
        'Razorpay Joiner Error: ${response.code} - ${response.message}',
      );
      if (mounted) {
        if ((response.code == 0 || response.code == 2) &&
            (razorpayKey == 'rzp_test_123' ||
                currentOrderId.startsWith('order_mock_'))) {
          final mockConfirmed = await ApiService.verifyJoinerPayment(
            cleanReqId.isNotEmpty ? cleanReqId : partyPlanId,
            currentOrderId,
            'pay_test_${DateTime.now().millisecondsSinceEpoch}',
            'test_signature',
          );
          if (mockConfirmed && mounted) {
            await onSuccess();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '🎉 Safety Deposit Paid! Match confirmed & Chat unlocked.',
                ),
                backgroundColor: Colors.green,
              ),
            );
            return;
          }
        }
        final isCancelled =
            response.code == Razorpay.PAYMENT_CANCELLED ||
            response.code == 2 ||
            response.code == 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCancelled
                  ? 'Payment cancelled.'
                  : 'Payment Failed: ${response.message ?? "Error"}',
            ),
            backgroundColor: isCancelled ? Colors.black87 : Colors.redAccent,
          ),
        );
      }
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (
      ExternalWalletResponse response,
    ) {
      razorpay.clear();
    });

    final options = <String, dynamic>{
      'key': razorpayKey,
      'amount': (depositAmount * 100).round(),
      'name': 'Lunara Joiner Deposit',
      'description': 'Safety deposit for Party Plan at $venueName',
      'currency': 'INR',
      if (currentOrderId.isNotEmpty) 'order_id': currentOrderId,
      'prefill': {'contact': '9999999999', 'email': 'user@lunara.app'},
      'theme': {'color': '#7C3AED'},
    };

    try {
      razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay for Joiner Payment: $e');
    }
  }

  Future<void> _handleConfirmStrangersMeetEndedDirect(String meetId) async {
    final actionKey = 'sm_end_$meetId';
    if (_activeActionKeys.contains(actionKey)) return;
    setState(() => _activeActionKeys.add(actionKey));

    try {
      await ApiService.confirmStrangersMeetEnded(meetId);
      if (mounted) {
        _loadFeed();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Meetup marked as ended. Admin will verify settlement.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF1E1E2E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activeActionKeys.remove(actionKey));
    }
  }

  Future<void> _handleMarkStrangersMeetNotStarted(String meetId) async {
    final actionKey = 'sm_not_started_$meetId';
    if (_activeActionKeys.contains(actionKey)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Mark as Not Started?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        content: const Text(
          'Are you sure this Strangers Meet did not take place? This will close the meetup.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Yes, Not Started',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _activeActionKeys.add(actionKey));
    try {
      await ApiService.reportStrangersMeetNotStarted(meetId);
      if (mounted) {
        _loadFeed();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Strangers Meet marked as not started.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF1E1E2E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activeActionKeys.remove(actionKey));
    }
  }
}
