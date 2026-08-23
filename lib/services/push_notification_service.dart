import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'notification_navigator.dart';
import '../core/theme.dart';
import '../widgets/top_notification_banner.dart';
import '../screens/social/chat_screen.dart';
import '../screens/discovery/venue_detail_screen.dart';
import '../screens/social/live_feed_screen.dart';
import '../screens/profile/lunara_wallet_screen.dart';
import '../screens/social/post_detail_screen.dart';
import '../screens/post_booking/ticket_pocket_screen.dart';
import '../screens/social/party_plan_requests_screen.dart';
import '../screens/social/host_party_plan_manager_screen.dart';
import '../screens/social/party_plan_detail_screen.dart';
import '../screens/social/notification_center_screen.dart';
import '../widgets/ad_announcement_dialog.dart';
import '../dialogs/party_plan_cancellation_dialog.dart';
import '../dialogs/strangers_meet_start_dialog.dart';
import '../dialogs/strangers_meet_end_dialog.dart';

/// Top-level background message handler.
/// Must be a top-level function (not a class method) for Firebase.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 Background message received: ${message.messageId}');
  // No need to show a notification here — the system tray handles it
  // automatically when the notification payload is present.
}

class PushNotificationService {
  PushNotificationService._();

  /// Currently open conversation ID — used to suppress popups for active chat screen
  static String? activeConversationId;

  /// Holds payload if notification tap occurs before main dashboard / navigator is ready
  static Map<String, dynamic>? pendingNotificationPayload;
  static bool isAppReady = false;

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Android notification channel for high-importance notifications.
  static const AndroidNotificationChannel _highImportanceChannel =
      AndroidNotificationChannel(
        'lunara_high_importance', // Must match AndroidManifest meta-data value
        'Lunara Notifications',
        description: 'Notifications for offers, messages, and events',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Mark the main UI app state as ready and process any pending notification tap
  static void setAppReady() {
    isAppReady = true;
    debugPrint('🔔 App marked as ready for deep link navigation');
    checkAndProcessPendingNotification();
  }

  /// Process pending notification payload if one was queued during cold start
  static void checkAndProcessPendingNotification() {
    if (pendingNotificationPayload != null && isAppReady) {
      final payload = pendingNotificationPayload!;
      pendingNotificationPayload = null;
      debugPrint('🔔 Processing queued cold-start notification deep link...');
      Future.delayed(const Duration(milliseconds: 400), () {
        navigateFromPayload(payload);
      });
    }
  }

  /// Call once after Firebase.initializeApp() and after the user is authenticated.
  static Future<void> initialize() async {
    // 1. Request permission (iOS + Android 13+)
    await _requestPermission();

    // 2. Create the Android notification channel
    await _createNotificationChannel();

    // 3. Initialize flutter_local_notifications for foreground display
    await _initLocalNotifications();

    // 4. Get the FCM token and send to backend
    await _registerToken();

    // 5. Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('🔔 FCM token refreshed');
      _sendTokenToBackend(newToken);
    });

    // 6. Foreground message handler — show a local notification & top banner
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 7. Register global real-time socket listeners for in-app floating banner
    ApiService.addSocketListener('notification_created', _onSocketNotificationReceived);
    ApiService.addSocketListener('notification_received', _onSocketNotificationReceived);
    ApiService.addSocketListener('push_notification', _onSocketNotificationReceived);
    ApiService.addSocketListener('new_ad_published', _onSocketAdPublished);
    ApiService.addSocketListener('strangers_meet_start_prompt', _onSocketStrangersMeetStartPrompt);
    ApiService.addSocketListener('strangers_meet_end_prompt', _onSocketStrangersMeetEndPrompt);
    ApiService.addSocketListener('party_plan_cancellation_requested', _onSocketPartyPlanCancellationRequested);

    // 8. Notification tap handler (app in background, not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('🔔 Notification opened from background: ${message.data}');
      _onNotificationTap(message);
    });

    // 9. Handle the case where app was opened from a terminated state (cold start)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🔔 App launched from terminated notification payload: ${initialMessage.data}');
      pendingNotificationPayload = initialMessage.data;
      checkAndProcessPendingNotification();
    }

    debugPrint('🔔 PushNotificationService initialized');
  }

  /// Call this immediately after a successful login / registration
  /// to ensure the FCM token is registered with the backend.
  /// Safe to call multiple times — it just re-sends the current token.
  static Future<void> registerTokenAfterLogin() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('🔔 Re-registering FCM token after login');
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('🔔 registerTokenAfterLogin error: $e');
    }
  }

  /// Call this when the user logs out.
  /// Unregisters FCM token from backend, deletes local device token, and cancels local notifications.
  static Future<void> unregisterTokenOnLogout() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('🔔 Unregistering FCM token from backend on logout');
        await ApiService.unregisterFcmToken(token);
      }
      await _messaging.deleteToken();
      await _localNotifications.cancelAll();
      debugPrint('🔔 FCM token deleted and local notifications cleared on logout');
    } catch (e) {
      debugPrint('🔔 unregisterTokenOnLogout error: $e');
    }
  }

  // ── Permission ──────────────────────────────────────────────────────────────

  static Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('🔔 Notification permission: ${settings.authorizationStatus}');
  }

  // ── Channel ─────────────────────────────────────────────────────────────────

  static Future<void> _createNotificationChannel() async {
    if (kIsWeb) return;
    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_highImportanceChannel);
      }
    } catch (e) {
      debugPrint('🔔 Error creating notification channel: $e');
    }
  }

  // ── Local Notifications Init ────────────────────────────────────────────────

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('launcher_icon');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );
  }

  // ── Token Registration ──────────────────────────────────────────────────────

  static Future<void> _registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('🔔 FCM Token: ${token.substring(0, 20)}...');
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('🔔 Error getting FCM token: $e');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiService.registerFcmToken(token);
    } catch (e) {
      debugPrint('🔔 Error sending FCM token to backend: $e');
    }
  }

  // ── Foreground Message ──────────────────────────────────────────────────────

  static void _onSocketNotificationReceived(dynamic data) {
    if (data == null) return;
    final Map<String, dynamic> notifMap = data is Map ? Map<String, dynamic>.from(data) : {};

    final title = (notifMap['title'] ?? notifMap['heading'] ?? notifMap['name'] ?? 'Notification').toString();
    final body = (notifMap['body'] ?? notifMap['message'] ?? '').toString();
    final senderData = notifMap['sender'] is Map ? Map<String, dynamic>.from(notifMap['sender']) : null;
    final payloadData = notifMap['data'] is Map ? Map<String, dynamic>.from(notifMap['data']) : notifMap;

    if (title.isEmpty && body.isEmpty) return;

    // Suppress popups if the user is currently looking at this exact chat screen
    final convId = payloadData['conversationId']?.toString();
    if (activeConversationId != null && convId != null && convId.toLowerCase() == activeConversationId!.toLowerCase()) {
      debugPrint('🔔 Suppressing in-app banner for active chat $activeConversationId');
      return;
    }

    debugPrint('🔔 Socket notification received in-app: $title - $body');

    TopNotificationBanner.show(
      title: title,
      body: body,
      data: payloadData,
      senderData: senderData,
    );
  }

  static void _onSocketAdPublished(dynamic data) {
    if (data == null) return;
    final Map<String, dynamic> notifMap = data is Map ? Map<String, dynamic>.from(data) : {};
    final adMap = notifMap['ad'] is Map ? Map<String, dynamic>.from(notifMap['ad']) : notifMap;

    final context = NotificationNavigator.navigatorKey.currentContext;
    if (context != null) {
      AdAnnouncementDialog.show(context, adMap);
    }
  }

  static void _onSocketStrangersMeetStartPrompt(dynamic data) {
    if (data == null) return;
    final Map<String, dynamic> meet = data is Map ? Map<String, dynamic>.from(data) : {};
    final context = NotificationNavigator.navigatorKey.currentContext;
    if (context != null) {
      final meetId = meet['id']?.toString() ?? meet['meetId']?.toString() ?? '';
      final subject = meet['subject']?.toString() ?? 'Strangers Meet';
      final venueName = meet['venue']?['name']?.toString() ?? meet['venueName']?.toString() ?? 'Venue';
      final rawDate = meet['eventDateTime']?.toString();
      final eventDate = rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;
      if (meetId.isNotEmpty) {
        StrangersMeetStartDialog.show(
          context,
          meetId: meetId,
          subject: subject,
          venueName: venueName,
          eventDateTime: eventDate ?? DateTime.now(),
        );
      }
    }
  }

  static void _onSocketStrangersMeetEndPrompt(dynamic data) {
    if (data == null) return;
    final Map<String, dynamic> meet = data is Map ? Map<String, dynamic>.from(data) : {};
    final context = NotificationNavigator.navigatorKey.currentContext;
    if (context != null) {
      final meetId = meet['id']?.toString() ?? meet['meetId']?.toString() ?? '';
      final subject = meet['subject']?.toString() ?? 'Strangers Meet';
      final venueName = meet['venue']?['name']?.toString() ?? meet['venueName']?.toString() ?? 'Venue';
      final rawEnd = meet['expectedEndAt']?.toString();
      final expectedEnd = rawEnd != null ? DateTime.tryParse(rawEnd)?.toLocal() : null;
      if (meetId.isNotEmpty) {
        StrangersMeetEndDialog.show(
          context,
          meetId: meetId,
          subject: subject,
          venueName: venueName,
          expectedEndAt: expectedEnd,
        );
      }
    }
  }

  static void _onSocketPartyPlanCancellationRequested(dynamic data) {
    if (data == null) return;
    final Map<String, dynamic> cancelMap = data is Map ? Map<String, dynamic>.from(data) : {};
    final context = NotificationNavigator.navigatorKey.currentContext;
    if (context != null) {
      final planId = cancelMap['planId']?.toString() ?? '';
      final requestId = cancelMap['requestId']?.toString() ?? '';
      final requesterName = cancelMap['requesterName']?.toString() ?? 'Participant';
      final requesterPhoto = cancelMap['requesterPhoto']?.toString();
      final planTitle = cancelMap['planTitle']?.toString() ?? 'Party Plan';
      final venueName = cancelMap['venueName']?.toString() ?? 'Selected Venue';
      final rawDate = cancelMap['eventDateTime']?.toString() ?? cancelMap['requestedAt']?.toString();
      final eventDate = rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;
      final reason = cancelMap['reason']?.toString() ?? 'personal_reasons';
      final otherReasonText = cancelMap['otherReasonText']?.toString();

      if (planId.isNotEmpty && requestId.isNotEmpty) {
        PartyPlanCancellationDialog.show(
          context,
          planId: planId,
          requestId: requestId,
          requesterName: requesterName,
          requesterPhoto: requesterPhoto,
          planTitle: planTitle,
          venueName: venueName,
          eventDateTime: eventDate ?? DateTime.now(),
          reason: reason,
          otherReasonText: otherReasonText,
        );
      }
    }
  }

  static void _onForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 Foreground FCM message received: ${message.messageId}');

    final notification = message.notification;
    final title = (notification?.title ?? message.data['title'] ?? message.data['heading'] ?? 'Notification').toString();
    final body = (notification?.body ?? message.data['body'] ?? message.data['message'] ?? '').toString();

    if (title.isEmpty && body.isEmpty) return;

    final convId = message.data['conversationId']?.toString();
    if (activeConversationId != null && convId != null && convId.toLowerCase() == activeConversationId!.toLowerCase()) {
      debugPrint('🔔 Suppressing foreground notification for active chat $activeConversationId');
      return;
    }

    final payload = jsonEncode(message.data);

    Color? notificationColor;
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('super')) {
      notificationColor = const Color(0xFFFFB800);
    } else if (lowerTitle.contains('like') || lowerTitle.contains('interest')) {
      notificationColor = const Color(0xFFE100FF);
    }

    _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _highImportanceChannel.id,
          _highImportanceChannel.name,
          channelDescription: _highImportanceChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          icon: 'launcher_icon',
          color: notificationColor,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );

    // Show WhatsApp-style top floating banner notification
    TopNotificationBanner.show(
      title: title,
      body: body,
      data: message.data,
    );
  }

  // ── Tap Handlers ────────────────────────────────────────────────────────────

  /// Called when a local notification (foreground) is tapped.
  static void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final rawMap = jsonDecode(response.payload!) as Map<String, dynamic>;
      final data = _normalizePayloadData(rawMap);
      if (!isAppReady) {
        pendingNotificationPayload = data;
      } else {
        navigateFromPayload(data);
      }
    } catch (e) {
      debugPrint('🔔 Error parsing local notification payload: $e');
    }
  }

  /// Called when a FCM notification (background) is tapped.
  static void _onNotificationTap(RemoteMessage message) {
    debugPrint('🔔 Notification tapped: ${message.data}');
    final data = _normalizePayloadData(message.data);
    if (!isAppReady) {
      debugPrint('🔔 App not ready yet — queueing notification payload');
      pendingNotificationPayload = data;
    } else {
      navigateFromPayload(data);
    }
  }

  // ── Navigation & Deep Link Resolution ───────────────────────────────────────

  static Map<String, dynamic> _normalizePayloadData(Map<String, dynamic> data) {
    final Map<String, dynamic> result = Map<String, dynamic>.from(data);

    if (data['data'] is Map) {
      result.addAll(Map<String, dynamic>.from(data['data']));
    } else if (data['data'] is String) {
      try {
        final parsed = jsonDecode(data['data']);
        if (parsed is Map) result.addAll(Map<String, dynamic>.from(parsed));
      } catch (_) {}
    }

    if (data['metadata'] is Map) {
      result.addAll(Map<String, dynamic>.from(data['metadata']));
    } else if (data['metadata'] is String) {
      try {
        final parsed = jsonDecode(data['metadata']);
        if (parsed is Map) result.addAll(Map<String, dynamic>.from(parsed));
      } catch (_) {}
    }

    return result;
  }

  static bool _isValidUuid(String str) {
    if (str.length < 32) return false;
    final uuidRegExp = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegExp.hasMatch(str);
  }

  static void navigateFromPayload(Map<String, dynamic> rawData) {
    final data = _normalizePayloadData(rawData);

    final navigator = NotificationNavigator.navigator;
    if (navigator == null) {
      debugPrint('🔔 Navigator not available yet — queueing payload for deep link');
      pendingNotificationPayload = data;
      return;
    }

    final rawType = (data['type'] ??
            data['eventType'] ??
            data['actionType'] ??
            data['event_type'] ??
            data['category'] ??
            data['entityType'] ??
            '')
        .toString()
        .toLowerCase()
        .trim();

    debugPrint('🔔 Navigating from notification payload (type: "$rawType", payload: $data)');

    // ── 1. Plan Upgrade, VIP Subscription & Wallet Notifications ────────────
    final isWalletOrSubscriptionType = rawType.contains('subscription') ||
        rawType.contains('upgrade') ||
        rawType.contains('vip') ||
        rawType.contains('tier') ||
        rawType.contains('membership') ||
        rawType.contains('wallet') ||
        rawType.contains('credit') ||
        rawType.contains('refund') ||
        rawType.contains('recharge') ||
        rawType.contains('deposit_refund');

    if (isWalletOrSubscriptionType) {
      if (rawType.contains('expired')) {
        _showSubscriptionDialog(
          navigator,
          title: 'VIP Subscription Expired',
          message: 'Your VIP subscription has expired or has been terminated. Tap below to view your wallet and options.',
          buttonText: 'View Wallet',
        );
      } else {
        navigator.push(
          MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
        );
      }
      return;
    }

    // ── 2. Messages & Chat Notifications ────────────────────────────────────
    final senderId = (data['senderId'] ??
            data['actorUserId'] ??
            data['actorId'] ??
            data['userId'])
        ?.toString();

    if (rawType.contains('message') ||
        rawType.contains('chat') ||
        (senderId != null && senderId.isNotEmpty && rawType == '')) {
      if (senderId != null && senderId.isNotEmpty) {
        _navigateToChat(navigator, data);
        return;
      }
    }

    // ── 3. Tickets & Booking Confirmations ──────────────────────────────────
    final isTicketType = rawType.contains('ticket') ||
        rawType.contains('booking_confirmed') ||
        rawType.contains('ticket_generated') ||
        rawType.contains('ticket_created') ||
        rawType.contains('pass') ||
        rawType.contains('entry_confirmed');

    if (isTicketType) {
      final partyPlanId = (data['partyPlanId'] ??
              data['planId'] ??
              data['entityId'] ??
              data['id'])
          ?.toString();

      final strangersMeetId = (data['strangersMeetRequestId'] ??
              data['strangersMeetId'] ??
              data['requestId'] ??
              data['meetId'] ??
              data['entityId'] ??
              data['id'])
          ?.toString();

      if (rawType.contains('stranger') || rawType.contains('meet')) {
        if (strangersMeetId != null && strangersMeetId.isNotEmpty && _isValidUuid(strangersMeetId)) {
          _navigateToStrangersMeet(navigator, strangersMeetId, data);
          return;
        }
      } else if (rawType.contains('party') || rawType.contains('plan')) {
        if (partyPlanId != null && partyPlanId.isNotEmpty && _isValidUuid(partyPlanId)) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => PartyPlanDetailScreen(
                plan: {'id': partyPlanId, 'planId': partyPlanId, ...data},
              ),
            ),
          );
          return;
        }
      }
      navigator.push(
        MaterialPageRoute(builder: (_) => const TicketPocketScreen()),
      );
      return;
    }

    // ── 4. Live Feed Direct Navigation ──────────────────────────────────────
    final isLiveFeedType = rawType.contains('live_feed') ||
        rawType.contains('feed') ||
        rawType.contains('activity') ||
        rawType.contains('timeline') ||
        rawType.contains('announcement');

    if (isLiveFeedType) {
      int initialTab = 0;
      if (rawType.contains('party') || rawType.contains('plan')) {
        initialTab = 1;
      } else if (rawType.contains('group') || rawType.contains('large')) {
        initialTab = 2;
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) => LiveFeedScreen(initialTabIndex: initialTab),
        ),
      );
      return;
    }

    // ── 5. Party Plan Notifications & Action Prompts ─────────────────────────
    final partyPlanId = (data['partyPlanId'] ??
            data['planId'] ??
            data['entityId'] ??
            data['id'])
        ?.toString();

    final isPartyPlanType = rawType.contains('party') ||
        rawType.contains('plan') ||
        rawType.contains('reminder') ||
        rawType.contains('cooldown') ||
        rawType.contains('arrival') ||
        rawType.contains('safety') ||
        rawType.contains('lock_expired') ||
        rawType.contains('deposit');

    if (isPartyPlanType) {
      if (partyPlanId != null && partyPlanId.isNotEmpty && _isValidUuid(partyPlanId)) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => PartyPlanDetailScreen(
              plan: {
                'id': partyPlanId,
                'planId': partyPlanId,
                ...data,
              },
            ),
          ),
        );
        return;
      }

      if (rawType.contains('request') || rawType.contains('participant')) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const PartyPlanRequestsScreen()),
        );
        return;
      }

      if (rawType.contains('host')) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const HostPartyPlanManagerScreen()),
        );
        return;
      }

      navigator.push(
        MaterialPageRoute(
          builder: (_) => const LiveFeedScreen(initialTabIndex: 1), // Tab 1 = Party Plan
        ),
      );
      return;
    }

    // ── 6. Stranger Meets Notifications ─────────────────────────────────────
    final strangersMeetId = (data['strangersMeetRequestId'] ??
            data['strangersMeetId'] ??
            data['requestId'] ??
            data['meetId'] ??
            data['entityId'] ??
            data['id'])
        ?.toString();

    final isStrangerMeetType = rawType.contains('stranger') || rawType.contains('meet');

    if (isStrangerMeetType) {
      if (strangersMeetId != null && strangersMeetId.isNotEmpty && _isValidUuid(strangersMeetId)) {
        _navigateToStrangersMeet(navigator, strangersMeetId, data);
        return;
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const LiveFeedScreen(initialTabIndex: 0), // Tab 0 = Stranger Meet
        ),
      );
      return;
    }

    // ── 7. Group Party / Large Party Bookings ───────────────────────────────
    if (rawType.contains('group') || rawType.contains('large_party')) {
      final status = (data['status'] ?? data['bookingStatus'] ?? '').toString().toLowerCase();
      if (status == 'confirmed' || status == 'paid' || rawType.contains('confirmed')) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const TicketPocketScreen()),
        );
      } else {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const LiveFeedScreen(initialTabIndex: 2), // Tab 2 = Group Parties
          ),
        );
      }
      return;
    }

    // ── 8. Venue Offers & Details ───────────────────────────────────────────
    final venueId = (data['venueId'] ?? data['entityId'] ?? data['id'])?.toString();
    if (rawType.contains('offer') || rawType.contains('venue') || rawType.contains('club')) {
      if (venueId != null && venueId.isNotEmpty) {
        _navigateToVenueDetail(navigator, data);
        return;
      }
    }

    // ── 9. Generic Bookings & Tickets ───────────────────────────────────────
    if (rawType.contains('booking')) {
      navigator.push(
        MaterialPageRoute(builder: (_) => const TicketPocketScreen()),
      );
      return;
    }

    // ── 10. Generic Fallbacks based on IDs ──────────────────────────────────
    if (partyPlanId != null && partyPlanId.isNotEmpty && _isValidUuid(partyPlanId)) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => PartyPlanDetailScreen(
            plan: {'id': partyPlanId, 'planId': partyPlanId, ...data},
          ),
        ),
      );
      return;
    }

    if (strangersMeetId != null && strangersMeetId.isNotEmpty && _isValidUuid(strangersMeetId)) {
      _navigateToStrangersMeet(navigator, strangersMeetId, data);
      return;
    }

    if (venueId != null && venueId.isNotEmpty && _isValidUuid(venueId)) {
      _navigateToVenueDetail(navigator, data);
      return;
    }

    if (senderId != null && senderId.isNotEmpty) {
      _navigateToChat(navigator, data);
      return;
    }

    // Fallback to Notification Center Screen
    navigator.push(
      MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
    );
  }

  static void _showSubscriptionDialog(
    NavigatorState navigator, {
    required String title,
    required String message,
    required String buttonText,
  }) {
    showDialog(
      context: navigator.context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          title: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Colors.black,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CLOSE',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: () {
                Navigator.pop(context);
                navigator.push(
                  MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
                );
              },
              child: Text(
                buttonText.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static void _navigateToVenueDetail(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) {
    final venueId = (data['venueId'] ?? data['entityId'] ?? data['id'])?.toString();
    final venueName = data['venueName']?.toString() ?? 'Venue';

    if (venueId == null || venueId.isEmpty) {
      debugPrint('🔔 Missing venueId in notification payload');
      return;
    }

    final venueMap = <String, dynamic>{
      'id': venueId,
      '_id': venueId,
      'name': venueName,
      'tagline': data['venueTagline'] ?? '',
      'city': data['venueCity'] ?? '',
      'area': data['venueArea'] ?? '',
      'description': data['venueDescription'] ?? '',
      'images': <Map<String, dynamic>>[],
    };

    navigator.push(
      MaterialPageRoute(builder: (_) => VenueDetailScreen(venue: venueMap)),
    );
  }

  static void _navigateToChat(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) {
    final senderId = (data['senderId'] ??
            data['actorUserId'] ??
            data['actorId'] ??
            data['userId'])
        ?.toString();
    final senderName = (data['senderName'] ??
            data['actorName'] ??
            data['name'] ??
            'User')
        .toString();
    final senderImage = (data['senderImage'] ??
            data['actorProfilePhotoUrl'] ??
            data['profileImageUrl'] ??
            data['imageUrl'])
        ?.toString();
    final conversationId = data['conversationId']?.toString();

    if (senderId == null || senderId.isEmpty) {
      debugPrint('🔔 Missing senderId in notification payload');
      return;
    }

    final userMap = <String, dynamic>{
      'id': senderId,
      'name': senderName,
      'firstName': senderName.split(' ').first,
      'lastName': senderName.split(' ').length > 1
          ? senderName.split(' ').sublist(1).join(' ')
          : '',
      'profilePhotoUrl': senderImage ?? '',
      'image': senderImage ?? '',
      'conversationId': conversationId,
    };

    navigator.push(
      MaterialPageRoute(builder: (_) => ChatScreen(user: userMap)),
    );
  }

  static void _navigateToStrangersMeet(
    NavigatorState navigator,
    String requestId,
    Map<String, dynamic> data,
  ) {
    navigator.push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: {
            'type': 'strangers_meet',
            'id': requestId,
            'requestId': requestId,
            ...data,
          },
        ),
      ),
    );
  }
}
