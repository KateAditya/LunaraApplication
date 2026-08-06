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
import '../widgets/ad_announcement_dialog.dart';

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

    // 8. Notification tap handler (app in background, not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    // 9. Handle the case where app was opened from a terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Small delay to let the navigator settle
      Future.delayed(const Duration(milliseconds: 800), () {
        _onNotificationTap(initialMessage);
      });
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
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      navigateFromPayload(data);
    } catch (e) {
      debugPrint('🔔 Error parsing local notification payload: $e');
    }
  }

  /// Called when a FCM notification (background) is tapped.
  static void _onNotificationTap(RemoteMessage message) {
    debugPrint('🔔 Notification tapped: ${message.data}');
    navigateFromPayload(message.data);
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  static void navigateFromPayload(Map<String, dynamic> data) {
    final navigator = NotificationNavigator.navigator;
    if (navigator == null) {
      debugPrint('🔔 Navigator not available yet — skipping navigation');
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
        .toLowerCase();

    switch (rawType) {
      // ── Strangers Meet Notifications (Tab 0 in LiveFeedScreen) ─────────────
      case 'strangers_meet_join_request':
      case 'strangers_meet_request_accepted':
      case 'strangers_meet_request_rejected':
      case 'strangers_meet_payment_success':
      case 'strangers_meet_participant_joined':
      case 'strangers_meet_approved':
      case 'strangers_meet_request_submitted':
      case 'strangers_meet_settlement_paid':
      case 'strangers_meet_published':
      case 'strangers_meet_awaiting_payment':
      case 'strangers_meet_starting_soon':
      case 'stranger_meet_request':
      case 'stranger_meet_accepted':
      case 'stranger_meet_declined':
      case 'stranger_meet_join_request':
      case 'stranger_meet_matched':
      case 'stranger_meet':
      case 'strangers_meet':
        final requestId = data['requestId']?.toString() ??
            data['id']?.toString() ??
            data['entityId']?.toString() ??
            data['strangersMeetRequestId']?.toString() ??
            data['meetId']?.toString();
        if (requestId != null && requestId.isNotEmpty) {
          _navigateToStrangersMeet(navigator, requestId);
        } else {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const LiveFeedScreen(initialTabIndex: 0), // Tab 0 = Stranger Meet
            ),
          );
        }
        break;

      // ── Venue Offers & Details ──────────────────────────────────────────────
      case 'offer':
      case 'club_pub_offer':
        _navigateToVenueDetail(navigator, data);
        break;

      // ── Messages & Chat ─────────────────────────────────────────────────────
      case 'message':
      case 'new_message':
      case 'match':
      case 'match_created':
        _navigateToChat(navigator, data);
        break;

      // ── Party Plan Notifications (Tab 1 in LiveFeedScreen) ──────────────────
      case 'new_party_plan':
      case 'party_plan_created':
      case 'party_plan_approved':
      case 'party_plan_published':
      case 'party_plan_starting_soon':
      case 'party_plan_joined':
      case 'party_plan_payment_success':
      case 'party_plan':
      case 'party_plan_declined':
      case 'party_safety_check':
      case 'cooldown_expiring_soon':
      case 'payment_window_expiring':
      case 'lock_expired':
      case 'reminder_24h':
      case 'reminder_3h':
      case 'reminder_2h':
      case 'reminder_1h':
      case 'reminder_30m':
      case 'reminder_10m':
      case 'arrival_prompt':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const LiveFeedScreen(initialTabIndex: 1), // Tab 1 = Party Plan
          ),
        );
        break;

      case 'participant_payment_required':
      case 'party_plan_request_accepted':
      case 'party_plan_request':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const PartyPlanRequestsScreen(),
          ),
        );
        break;

      case 'host_payment_required':
      case 'host_payment_successful':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const HostPartyPlanManagerScreen(),
          ),
        );
        break;

      // ── Group Party Notifications (Tab 2 in LiveFeedScreen) ────────────────
      case 'group_party_initiated':
      case 'group_party_approved':
      case 'group_party_rejected':
      case 'group_party_confirmed':
      case 'group_party_cancelled':
      case 'group_invite_sent':
      case 'group_invite_accepted':
      case 'group_member_joined':
      case 'group_full':
      case 'group_party':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const LiveFeedScreen(initialTabIndex: 2), // Tab 2 = Group Parties
          ),
        );
        break;

      // ── Bookings & Digital Tickets ──────────────────────────────────────────
      case 'booking_confirmed':
      case 'booking_pending':
      case 'booking_cancelled':
      case 'booking_completed':
      case 'large_party_confirmed':
      case 'large_party_approved':
      case 'large_party_payment_link':
      case 'large_party_pending':
      case 'large_party_rejected':
      case 'ticket_generated':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const TicketPocketScreen(),
          ),
        );
        break;

      // ── Subscription Notifications ──────────────────────────────────────────
      case 'subscription_expired':
        _showSubscriptionDialog(
          navigator,
          title: 'VIP Subscription Expired',
          message: 'Your VIP subscription has expired or has been terminated. Tap below to view your wallet and options.',
          buttonText: 'View Wallet',
        );
        break;

      case 'subscription_extended':
        _showSubscriptionDialog(
          navigator,
          title: 'VIP Subscription Extended!',
          message: 'Excellent news! Your VIP subscription has been extended by the administration. Tap below to check your updated status.',
          buttonText: 'Check Wallet',
        );
        break;

      default:
        // Smart fallback matcher based on payload string contents
        if (rawType.contains('party_plan') || rawType.contains('plan')) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const LiveFeedScreen(initialTabIndex: 1), // Party Plan tab
            ),
          );
        } else if (rawType.contains('stranger') || rawType.contains('meet')) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const LiveFeedScreen(initialTabIndex: 0), // Stranger Meet tab
            ),
          );
        } else if (rawType.contains('group')) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const LiveFeedScreen(initialTabIndex: 2), // Group Parties tab
            ),
          );
        } else {
          debugPrint('🔔 Unknown notification type: $rawType');
        }
    }
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
    final venueId = data['venueId']?.toString();
    final venueName = data['venueName']?.toString() ?? 'Venue';

    if (venueId == null || venueId.isEmpty) {
      debugPrint('🔔 Missing venueId in notification payload');
      return;
    }

    // Build a minimal venue map that VenueDetailScreen can work with.
    // The screen will fetch full details from the API if needed.
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
    final senderId = data['senderId']?.toString();
    final senderName = data['senderName']?.toString() ?? 'User';
    final senderImage = data['senderImage']?.toString();
    final conversationId = data['conversationId']?.toString();

    if (senderId == null || senderId.isEmpty) {
      debugPrint('🔔 Missing senderId in notification payload');
      return;
    }

    // Build a user map that ChatScreen expects.
    final userMap = <String, dynamic>{
      'id': senderId,
      'name': senderName,
      'firstName': senderName.split(' ').first,
      'lastName': senderName.split(' ').length > 1
          ? senderName.split(' ').sublist(1).join(' ')
          : '',
      'image': senderImage ?? '',
      'conversationId': conversationId,
    };

    navigator.push(
      MaterialPageRoute(builder: (_) => ChatScreen(user: userMap)),
    );
  }

  static void _navigateToStrangersMeet(NavigatorState navigator, String requestId) {
    navigator.push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: {
            'type': 'strangers_meet',
            'id': requestId,
          },
        ),
      ),
    );
  }
}
