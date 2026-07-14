import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'notification_navigator.dart';
import '../core/theme.dart';
import '../screens/social/chat_screen.dart';
import '../screens/discovery/venue_detail_screen.dart';
import '../screens/social/live_feed_screen.dart';
import '../screens/profile/lunara_wallet_screen.dart';

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

    // 6. Foreground message handler — show a local notification
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 7. Notification tap handler (app in background, not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTap);

    // 8. Handle the case where app was opened from a terminated state
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

  static void _onForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 Foreground message: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    // Encode the data payload into the notification so we can read it on tap
    final payload = jsonEncode(message.data);

    Color? notificationColor;
    if (notification.title?.toLowerCase().contains('super') == true) {
      notificationColor = const Color(0xFFFFB800); // Gold/Amber
    } else if (notification.title?.toLowerCase().contains('like') == true) {
      notificationColor = const Color(0xFFE100FF); // Hot Pink
    }

    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _highImportanceChannel.id,
          _highImportanceChannel.name,
          channelDescription: _highImportanceChannel.description,
          importance: Importance.high,
          priority: Priority.high,
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
  }

  // ── Tap Handlers ────────────────────────────────────────────────────────────

  /// Called when a local notification (foreground) is tapped.
  static void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _navigateFromPayload(data);
    } catch (e) {
      debugPrint('🔔 Error parsing local notification payload: $e');
    }
  }

  /// Called when a FCM notification (background) is tapped.
  static void _onNotificationTap(RemoteMessage message) {
    debugPrint('🔔 Notification tapped: ${message.data}');
    _navigateFromPayload(message.data);
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  static void _navigateFromPayload(Map<String, dynamic> data) {
    final navigator = NotificationNavigator.navigator;
    if (navigator == null) {
      debugPrint('🔔 Navigator not available yet — skipping navigation');
      return;
    }

    final type = data['type']?.toString() ?? '';

    switch (type) {
      case 'offer':
      case 'club_pub_offer':
        _navigateToVenueDetail(navigator, data);
        break;
      case 'message':
      case 'new_message': // Backend sends 'new_message' for chat notifications
      case 'match': // Navigate to chat on mutual match
        _navigateToChat(navigator, data);
        break;
      case 'new_party_plan':
      case 'host_payment_successful':
      case 'participant_payment_required':
      case 'booking_confirmed':
      case 'ticket_generated':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
          ),
        );
        break;
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
        debugPrint('🔔 Unknown notification type: $type');
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
}
