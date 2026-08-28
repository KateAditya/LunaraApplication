import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';

/// Production-Grade Centralized Realtime Sync Manager for Lunara.
/// Handles event-driven updates, deduplication, versioning, delta sync,
/// and visibility-aware lifecycle management.
class RealtimeSyncManager with WidgetsBindingObserver {
  static final RealtimeSyncManager _instance = RealtimeSyncManager._internal();
  static RealtimeSyncManager get instance => _instance;

  RealtimeSyncManager._internal() {
    _initLifecycleObserver();
  }

  // ── Lifecycle & State Tracking ─────────────────────────────────────────────
  bool _isInitialized = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  DateTime _lastSyncAt = DateTime.now().subtract(const Duration(minutes: 5));
  Timer? _fallbackSyncTimer;
  bool _isSyncing = false;

  // ── Event Deduplication Cache (LRU max 500) ───────────────────────────────
  final Map<String, int> _processedEventIds = {};
  static const int _maxDeduplicationEntries = 500;

  // ── Entity Version & Freshness Map ─────────────────────────────────────────
  final Map<String, int> _entityVersions = {};
  final Map<String, DateTime> _entityTimestamps = {};

  // ── Granular ValueNotifiers for Targeted Auto-Rendering ────────────────────
  final ValueNotifier<Map<String, dynamic>?> partyPlanNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> recentPostsNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> strangerMeetNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> groupPartyNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> venueNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> profileNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> walletNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> notificationNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> vipStatusNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> chatNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> ticketNotifier = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>?> liveFeedNotifier = ValueNotifier(null);
  final ValueNotifier<int> globalSyncTick = ValueNotifier(0);

  /// Trigger an immediate local UI refresh & broadcast to all active screens
  void triggerLocalUpdate(String eventType, [dynamic payload]) {
    handleIncomingEvent(eventType, payload ?? {'timestamp': DateTime.now().toIso8601String()});
    globalSyncTick.value++;
    ApiService.planPostedNotifier.value++;
  }

  // ── Initialization & Socket Binding ────────────────────────────────────────
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    _bindSocketEvents();
    _startAdaptiveFallback();
  }

  void _initLifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      // Returned to foreground: resume adaptive fallback & reconcile delta if needed
      _startAdaptiveFallback();
      final diff = DateTime.now().difference(_lastSyncAt);
      if (diff.inSeconds >= 15) {
        reconcileDelta();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // In background/hidden: STOP polling to preserve battery, CPU & avoid server load
      _stopAdaptiveFallback();
    }
  }

  // ── Event Deduplication & Version Verification ─────────────────────────────
  bool _isDuplicateOrStale(String eventId, String entityId, int? version, String? updatedAt) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Check Event ID Deduplication
    if (eventId.isNotEmpty) {
      if (_processedEventIds.containsKey(eventId)) {
        return true; // Duplicate delivery
      }
      _processedEventIds[eventId] = now;
      if (_processedEventIds.length > _maxDeduplicationEntries) {
        // Evict oldest entries
        final oldestKey = _processedEventIds.keys.first;
        _processedEventIds.remove(oldestKey);
      }
    }

    // 2. Check Version / Timestamp Freshness
    if (entityId.isNotEmpty) {
      if (version != null && version > 0) {
        final existingVersion = _entityVersions[entityId];
        if (existingVersion != null && version < existingVersion) {
          return true; // Stale version
        }
        _entityVersions[entityId] = version;
      }

      if (updatedAt != null && updatedAt.isNotEmpty) {
        try {
          final incomingDt = DateTime.parse(updatedAt);
          final existingDt = _entityTimestamps[entityId];
          if (existingDt != null && incomingDt.isBefore(existingDt)) {
            return true; // Stale timestamp
          }
          _entityTimestamps[entityId] = incomingDt;
        } catch (_) {}
      }
    }

    return false;
  }

  // ── Dispatch Incoming Realtime Event ───────────────────────────────────────
  void handleIncomingEvent(String eventType, dynamic rawPayload) {
    if (rawPayload == null) return;
    Map<String, dynamic> payload = {};
    if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else {
      payload = {'data': rawPayload};
    }

    final eventId = (payload['eventId'] ?? '').toString();
    final entity = (payload['entity'] ?? '').toString().toLowerCase();
    final entityId = (payload['entityId'] ?? payload['id'] ?? payload['_id'] ?? '').toString();
    final version = payload['version'] is num ? (payload['version'] as num).toInt() : int.tryParse(payload['version']?.toString() ?? '');
    final updatedAt = payload['updatedAt']?.toString() ?? payload['timestamp']?.toString();

    // Check deduplication
    if (eventId.isNotEmpty && _isDuplicateOrStale(eventId, entityId, version, updatedAt)) {
      return;
    }

    final eventData = payload['data'] is Map ? Map<String, dynamic>.from(payload['data']) : payload;

    // Route to targeted entity stores
    _routeEventToTargetStores(eventType, entity, entityId, eventData);
  }

  void _routeEventToTargetStores(String eventType, String entity, String entityId, Map<String, dynamic> data) {
    final eventEnvelope = {
      'eventType': eventType,
      'entity': entity,
      'entityId': entityId,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // 1. Party Plan & Recent Posts
    if (eventType.startsWith('party_plan_') || eventType.startsWith('post_') || entity == 'party_plan' || entity == 'post') {
      partyPlanNotifier.value = eventEnvelope;
      recentPostsNotifier.value = eventEnvelope;
      liveFeedNotifier.value = eventEnvelope;
    }

    // 2. Stranger Meets
    if (eventType.startsWith('strangers_meet_') || entity == 'stranger_meet') {
      strangerMeetNotifier.value = eventEnvelope;
      recentPostsNotifier.value = eventEnvelope;
      liveFeedNotifier.value = eventEnvelope;
    }

    // 3. Group Parties & Large Parties
    if (eventType.startsWith('group_party_') || eventType.startsWith('large_party_') || entity == 'group_party' || entity == 'large_party') {
      groupPartyNotifier.value = eventEnvelope;
      liveFeedNotifier.value = eventEnvelope;
    }

    // 4. Venues, Upcoming Nights & Events
    if (eventType.startsWith('venue_') || eventType.startsWith('event_') || eventType.startsWith('ad_') || entity == 'venue' || entity == 'event' || entity == 'ad') {
      venueNotifier.value = eventEnvelope;
    }

    // 5. User Profiles, Photos, Connections
    if (eventType.startsWith('profile_') || eventType == 'user_status_changed' || entity == 'user') {
      profileNotifier.value = eventEnvelope;
      ApiService.profileUpdateNotifier.value++;
    }

    // 6. Social Likes / Super Likes / Matches
    if (eventType == 'like_created' || eventType == 'superlike_created' || eventType == 'like_removed' || eventType == 'new_match') {
      profileNotifier.value = eventEnvelope;
      notificationNotifier.value = eventEnvelope;
    }

    // 7. Wallet & Credits
    if (eventType.startsWith('wallet_') || entity == 'wallet') {
      walletNotifier.value = eventEnvelope;
    }

    // 8. Notifications & Badges
    if (eventType.startsWith('notification_') || eventType == 'badge_updated' || entity == 'notification') {
      notificationNotifier.value = eventEnvelope;
      liveFeedNotifier.value = eventEnvelope;
    }

    // 9. VIP & Subscriptions
    if (eventType.startsWith('subscription_') || eventType.startsWith('vip_') || eventType == 'boost_activated' || entity == 'vip') {
      vipStatusNotifier.value = eventEnvelope;
    }

    // 10. Chats & Messages
    if (eventType.startsWith('chat_') || eventType.startsWith('message') || eventType == 'new_message' || entity == 'chat') {
      chatNotifier.value = eventEnvelope;
    }

    // 11. Tickets & Gate Scans
    if (eventType.startsWith('ticket_') || eventType == 'party_plan_ticket_generated' || entity == 'ticket') {
      ticketNotifier.value = eventEnvelope;
    }
  }

  // ── Socket Events Binding ──────────────────────────────────────────────────
  void _bindSocketEvents() {
    // Canonical realtime_event envelope
    ApiService.addSocketListener('realtime_event', (payload) => handleIncomingEvent('realtime_event', payload));

    // Standardized events
    const eventTypes = [
      'party_plan_created',
      'party_plan_updated',
      'party_plan_deleted',
      'party_plan_reposted',
      'party_plan_cancelled',
      'post_created',
      'post_updated',
      'post_deleted',
      'event_created',
      'event_updated',
      'ad_created',
      'ad_updated',
      'party_plan_request_created',
      'party_plan_request_received',
      'party_plan_request_updated',
      'party_plan_request_cancelled',
      'party_plan_request_rejected',
      'party_plan_request_accepted',
      'party_plan_match_success',
      'party_plan_host_paid',
      'party_plan_joiner_paid',
      'party_plan_ticket_generated',
      'party_plan_arrival_confirmed',
      'strangers_meet_created',
      'strangers_meet_updated',
      'strangers_meet_joiner_joined',
      'strangers_meet_host_paid',
      'strangers_meet_joiner_paid',
      'strangers_meet_arrival_confirmed',
      'strangers_meet_started',
      'strangers_meet_settled',
      'strangers_meet_status_update',
      'group_party_payment_success',
      'group_party_status_update',
      'large_party_status_update',
      'venue_created',
      'venue_updated',
      'venue_deleted',
      'venue_booking_status_update',
      'profile_updated',
      'profile_photo_updated',
      'user_status_changed',
      'like_created',
      'superlike_created',
      'like_removed',
      'new_match',
      'wallet_updated',
      'wallet_refund_processed',
      'notification_created',
      'notification_received',
      'notification_updated',
      'badge_updated',
      'subscription_updated',
      'subscription_expired',
      'subscription_expiring',
      'vip_activated',
      'boost_activated',
      'ticket_updated',
      'ticket_status_update',
      'new_message',
      'messages_read',
      'messages_delivered',
      'chat_badge_updated',
    ];

    for (final event in eventTypes) {
      ApiService.addSocketListener(event, (payload) => handleIncomingEvent(event, payload));
    }
  }

  // ── Delta Reconciliation ───────────────────────────────────────────────────
  Future<void> reconcileDelta() async {
    if (_isSyncing) return;
    if (ApiService.currentUserId == null || ApiService.authToken == null) return;
    if (_appLifecycleState != AppLifecycleState.resumed) return;

    _isSyncing = true;
    try {
      final delta = await ApiService.fetchDeltaSync(_lastSyncAt);
      if (delta != null && delta['success'] == true) {
        _lastSyncAt = DateTime.now();
        final data = delta['data'] as Map<String, dynamic>? ?? {};

        // 1. Unread notification badge
        if (data['unreadNotificationCount'] is num) {
          final count = (data['unreadNotificationCount'] as num).toInt();
          notificationNotifier.value = {
            'eventType': 'badge_updated',
            'data': {'unreadCount': count},
          };
        }

        // 2. Unread chat count
        if (data['unreadChatCount'] is num) {
          final chatCount = (data['unreadChatCount'] as num).toInt();
          ApiService.updateChatBadgeCount(chatCount);
        }

        // 3. Wallet
        if (data['wallet'] is Map) {
          walletNotifier.value = {
            'eventType': 'wallet_updated',
            'data': data['wallet'],
          };
        }

        // 4. Subscription
        if (data['subscription'] is Map) {
          vipStatusNotifier.value = {
            'eventType': 'subscription_updated',
            'data': data['subscription'],
          };
        }

        // 5. Party Plans & Requests
        final updatedPlans = data['partyPlans'] as List? ?? [];
        final updatedReqs = data['partyPlanRequests'] as List? ?? [];
        if (updatedPlans.isNotEmpty || updatedReqs.isNotEmpty) {
          partyPlanNotifier.value = {
            'eventType': 'delta_sync',
            'data': {'plans': updatedPlans, 'requests': updatedReqs},
          };
          liveFeedNotifier.value = partyPlanNotifier.value;
        }

        // 6. Stranger Meets
        final updatedMeets = data['strangerMeets'] as List? ?? [];
        final updatedMeetParts = data['strangerMeetParticipations'] as List? ?? [];
        if (updatedMeets.isNotEmpty || updatedMeetParts.isNotEmpty) {
          strangerMeetNotifier.value = {
            'eventType': 'delta_sync',
            'data': {'meets': updatedMeets, 'participations': updatedMeetParts},
          };
          liveFeedNotifier.value = strangerMeetNotifier.value;
        }

        globalSyncTick.value++;
      }
    } catch (e) {
      debugPrint('[RealtimeSyncManager] Delta sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ── Adaptive Fallback Polling (Offline / Disconnected Only) ────────────────
  void _startAdaptiveFallback() {
    _fallbackSyncTimer?.cancel();
    // Check if socket is disconnected every 30 seconds only while in foreground
    _fallbackSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_appLifecycleState != AppLifecycleState.resumed) return;
      final isSocketConnected = ApiService.socket?.connected ?? false;
      if (!isSocketConnected) {
        // Socket is offline: execute gentle fallback reconciliation
        reconcileDelta();
      }
    });
  }

  void _stopAdaptiveFallback() {
    _fallbackSyncTimer?.cancel();
    _fallbackSyncTimer = null;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAdaptiveFallback();
  }
}
