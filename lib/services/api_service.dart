import 'dart:io' show HttpClient, Platform, SocketException;
import 'dart:convert';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/venue.dart';
import '../models/user.dart';
import '../models/package.dart';
import '../models/help_article.dart';
import '../models/community_guideline.dart';
import '../models/legal_document.dart';
import '../models/strangers_meet_request.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'notification_navigator.dart';
import 'push_notification_service.dart';
import 'subscription_provider.dart';
import 'realtime_sync_manager.dart';
import 'image_cache_service.dart';
import '../screens/auth/autoblocked_warning_screen.dart';

class ApiService {
  // Toggle this to true to use your local backend, false for production
  static const bool isLocal = false;

  /// Reusable HTTP client instance for connection pooling & Keep-Alive.
  static final http.Client _httpClient = _createHttpClient();

  /// How long to wait for a TCP connection before giving up on it.
  ///
  /// A plain `http.Client()` leaves `connectionTimeout` unset, which hands a
  /// failed TCP handshake to the operating system's SYN retransmission backoff
  /// — roughly 1s + 2s + 4s + 8s. Measured against the production backend, ~4%
  /// of fresh connections lose their SYN and stall for 6-14 seconds while the
  /// server itself answers in under 100ms. Because the app opens its connection
  /// at launch and then reuses it, drawing that stall on the first request froze
  /// startup for the full backoff.
  ///
  /// A normal connect to this backend takes ~20ms (slowest healthy sample:
  /// 153ms), so 4 seconds is orders of magnitude above legitimate latency —
  /// generous even for a poor mobile network — while cutting a stalled handshake
  /// to a fraction of the OS default. [get] then retries on a brand-new socket,
  /// whose SYN almost always gets through immediately.
  static const Duration _connectTimeout = Duration(seconds: 4);

  static http.Client _createHttpClient() {
    // dart:io is unavailable in a browser; there the package default is correct.
    if (kIsWeb) return http.Client();
    final inner = HttpClient()
      ..connectionTimeout = _connectTimeout
      // Hold an established connection open between requests so the handshake
      // — and the chance of drawing a stalled one — is paid far less often.
      // The package default drops it after 15s of idle.
      ..idleTimeout = const Duration(seconds: 60);
    return IOClient(inner);
  }

  /// Default network timeout to prevent hanging on flaky connections while allowing
  /// cloud services (Azure App Service / Postgres) sufficient time to respond under load.
  static const Duration defaultTimeout = Duration(seconds: 35);

  /// Extended timeout for transactional operations (booking creation, payment verification, refunds)
  static const Duration transactionalTimeout = Duration(seconds: 45);

  /// Concurrent in-flight GET request deduplication pool to prevent duplicate network calls
  static final Map<String, Future<http.Response>> _inFlightGets = {};
  static DateTime? _lastProfileFetchTime;

  // ── High-Speed In-Memory Cache with Instant Stale-While-Revalidate ────────
  static final Map<String, List<Venue>> _cachedVenuesByCity = {};
  static final Map<String, DateTime> _venuesCacheTimestamps = {};

  static final Map<String, List<Map<String, dynamic>>> _cachedAds = {};
  static final Map<String, DateTime> _adsCacheTimestamps = {};

  static final Map<String, List<Package>> _cachedPackagesByVenue = {};
  static final Map<String, DateTime> _packagesCacheTimestamps = {};

  static final Map<String, List<Map<String, dynamic>>> _cachedPartyPlans = {};
  static final Map<String, DateTime> _partyPlansCacheTimestamps = {};

  static final Map<String, List<Map<String, dynamic>>> _cachedCustomers = {};
  static final Map<String, DateTime> _customersCacheTimestamps = {};

  static final Map<String, List<Map<String, dynamic>>>
  _cachedStrangersMeetFeed = {};
  static final Map<String, DateTime> _strangersMeetFeedCacheTimestamps = {};

  static final Map<String, String> _userTierMap = {};

  /// Register a user's subscription tier in the global cache for instant ring resolution across the app
  static void registerUserTier(String? userId, String? tier) {
    if (userId != null &&
        userId.isNotEmpty &&
        tier != null &&
        tier.isNotEmpty &&
        tier.toUpperCase() != 'FREE') {
      _userTierMap[userId] = tier.toUpperCase();
    }
  }

  /// Synchronously get cached subscription tier for any user ID
  static String? getUserTier(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    return _userTierMap[userId];
  }

  static Map<String, dynamic>? _cachedWalletBalance;
  static DateTime? _walletBalanceCacheTime;

  static Map<String, dynamic>? _cachedWalletData;
  static DateTime? _walletDataCacheTime;

  static Map<String, dynamic>? _cachedLiveFeedData;
  static DateTime? _liveFeedCacheTime;

  static List<Map<String, dynamic>>? _cachedNotifications;
  static DateTime? _notificationsCacheTime;

  /// Group parties (<= 20 friends), as consumed by [fetchMyLargePartyBookings].
  ///
  /// This request used to run unconditionally on every live-feed refresh — it
  /// was the one leg of that five-call fan-out with no cache at all, so a burst
  /// of realtime events meant a burst of group-party round trips.
  static List<Map<String, dynamic>>? _cachedGroupParties;
  static DateTime? _groupPartiesCacheTime;

  static List<Map<String, dynamic>>? _cachedAddonPackages;
  static DateTime? _addonPackagesCacheTime;

  static List<dynamic>? _cachedSubscriptionPackages;
  static DateTime? _subscriptionPackagesCacheTime;

  /// Last known tickets, regardless of age.
  ///
  /// Ticket Pocket is a pushed route, so its State is rebuilt from scratch every
  /// time it is opened. Waiting for the network on each visit is what made it
  /// "fast one time, slow the next" — a hit inside the 30s window painted
  /// instantly, anything later showed a spinner. Screens hydrate from this
  /// first and let [fetchAllUserTickets] refresh underneath.
  static List<Map<String, dynamic>>? get cachedTickets => _cachedTickets;

  /// Last known conversations, regardless of age. See [cachedTickets].
  static List<Map<String, dynamic>>? get cachedConversations =>
      _cachedConversations;

  static List<Map<String, dynamic>>? _cachedConversations;
  static DateTime? _conversationsCacheTime;

  static Map<String, dynamic>? get cachedLiveFeedData => _cachedLiveFeedData;
  static List<Map<String, dynamic>>? get cachedNotifications =>
      _cachedNotifications;

  // Uses your machine's local IP (192.168.0.154) for local dev on a real device
  static String get baseUrl {
    if (!isLocal) {
      return 'https://lunara-backend-api-e3hhhmc2g0c2hgd0.centralindia-01.azurewebsites.net';
    }
    if (kIsWeb) {
      return 'http://localhost:9076';
    }
    return 'http://192.168.0.154:9076';
  }

  static String? _authToken;
  static String? selectedCity;
  static User? cachedCurrentUser;

  static final ValueNotifier<int> profileUpdateNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> planPostedNotifier = ValueNotifier<int>(0);

  /// Centralized trigger to instantly refresh the Live Feed and associated views across the app.
  static void notifyFeedNeedsRefresh() {
    clearBookingCache();
    planPostedNotifier.value++;
    RealtimeSyncManager.instance.triggerLiveFeedSync();
    RealtimeSyncManager.instance.triggerPartyPlanSync();
    RealtimeSyncManager.instance.triggerStrangerMeetSync();
  }

  /// Marks bookings, notifications and badge caches stale so the next read
  /// refetches from the server.
  ///
  /// Only the *timestamps* are cleared, never the payloads. Every `fetch*`
  /// helper treats a missing timestamp as expired, so freshness is unchanged —
  /// the very next call still goes to the network. What the retained payload
  /// buys is the first frame: a screen re-entered after this call can paint the
  /// last known content immediately through the `cached*` getters and swap in
  /// fresh data when it lands, instead of showing an empty spinner while it
  /// waits. Discarding the payload here is what made the Live Feed blank out
  /// after every plan action.
  static void clearBookingCache() {
    _liveFeedCacheTime = null;
    _notificationsCacheTime = null;
    _bookingsCacheTime = null;
    _groupPartiesCacheTime = null;
    _badgeCountsCacheTime = null;
    _addonPackagesCacheTime = null;
    _subscriptionPackagesCacheTime = null;
    _ticketsCacheTime = null;
    _conversationsCacheTime = null;
    _safetyCheckCacheTime = null;
    _strangersMeetFeedCacheTimestamps.clear();
    _partyPlansCacheTimestamps.clear();
  }

  // ── Synchronous Local Request Status Cache for Instant UI Rendering ────────
  static final Set<String> _cachedRequestedPlanIds = {};
  static final Map<String, Map<String, dynamic>> _cachedPartyPlanRequests = {};
  static String? _localStateUserId;

  /// Changes to the signed-in account must never reuse device-local activity
  /// state from the previous account. Server data remains the source of truth.
  static final ValueNotifier<int> authSessionNotifier = ValueNotifier<int>(0);

  static String _userPreferenceKey(String base, String userId) =>
      '$base.$userId';

  static void _ensureLocalStateForCurrentUser() {
    final userId = currentUserId;
    if (_localStateUserId == userId) return;

    _localStateUserId = userId;
    _cachedRequestedPlanIds.clear();
    _cachedPartyPlanRequests.clear();
    localReadNotificationIds.clear();
    localReadRequestIds.clear();
    _readIdsLoaded = false;
    _cachedLiveFeedData = null;
    _liveFeedCacheTime = null;
    _cachedNotifications = null;
    _notificationsCacheTime = null;
    _cachedGroupParties = null;
    _groupPartiesCacheTime = null;
    _cachedWalletBalance = null;
    _walletBalanceCacheTime = null;
    _cachedWalletData = null;
    _walletDataCacheTime = null;
    _cachedAddonPackages = null;
    _addonPackagesCacheTime = null;
    _cachedSubscriptionPackages = null;
    _subscriptionPackagesCacheTime = null;
  }

  /// Immediately invalidates the 5-second live feed data cache so that
  /// the next call to fetchLiveFeedData fetches fresh backend state.
  static void invalidateLiveFeedCache() {
    _cachedLiveFeedData = null;
    _liveFeedCacheTime = null;
  }

  /// Expires only the caches a Party Plan / live-feed event can actually change.
  ///
  /// `clearBookingCache` expires *every* cache timestamp. Running it for each
  /// realtime party-plan event therefore sent bookings, group parties, tickets,
  /// conversations and the safety check back to the network as well — round
  /// trips that event could not possibly have invalidated, on every single
  /// request, acceptance and cancellation. Same retain-the-payload semantics as
  /// `clearBookingCache`: only the timestamps go, so screens still paint their
  /// last known content on the first frame.
  static void invalidateLiveFeedAndNotificationCaches() {
    _liveFeedCacheTime = null;
    _notificationsCacheTime = null;
    _badgeCountsCacheTime = null;
  }

  /// Synchronously returns whether the current user has requested to join a given party plan.
  static bool isPartyPlanRequestedSync(String planId) {
    if (planId.isEmpty) return false;
    return _cachedRequestedPlanIds.contains(planId);
  }

  /// Synchronously returns cached request details for a given party plan.
  static Map<String, dynamic>? getCachedPartyPlanRequestSync(String planId) {
    if (planId.isEmpty) return null;
    return _cachedPartyPlanRequests[planId];
  }

  /// Synchronously returns all plan IDs current user has requested to join.
  static Set<String> getRequestedPlanIdsSync() {
    return Set<String>.from(_cachedRequestedPlanIds);
  }

  static final Map<String, Map<String, dynamic>> _optimisticPartyPlans = {};

  /// Synchronously registers a newly created or updated party plan for 0ms instant display in Live Feed
  static void registerOptimisticPartyPlan(Map<String, dynamic> planData) {
    final id =
        (planData['id'] ?? planData['partyPlanId'] ?? planData['planId'])
            ?.toString() ??
        '';
    if (id.isEmpty) return;
    _optimisticPartyPlans[id] = Map<String, dynamic>.from(planData);
    notifyFeedNeedsRefresh();
  }

  static void removeOptimisticPartyPlan(String planId) {
    if (planId.isEmpty) return;
    _optimisticPartyPlans.remove(planId);
  }

  /// Mark a party plan as requested locally for instant UI responsiveness.
  static void markPartyPlanAsRequestedLocal(
    String planId, [
    Map<String, dynamic>? requestData,
  ]) {
    _ensureLocalStateForCurrentUser();
    if (planId.isEmpty) return;
    _cachedRequestedPlanIds.add(planId);
    _cachedPartyPlanRequests[planId] =
        requestData ??
        {
          'id': 'local_$planId',
          'planId': planId,
          'partyPlanId': planId,
          'status': 'pending',
          'joinerPaymentStatus': 'unpaid',
          'createdAt': DateTime.now().toIso8601String(),
        };
    _saveCachedRequestsToPrefs();
  }

  /// Mark a party plan as cancelled/declined locally.
  static void markPartyPlanAsCancelledLocal(String planId) {
    _ensureLocalStateForCurrentUser();
    if (planId.isEmpty) return;
    _cachedRequestedPlanIds.remove(planId);
    _cachedPartyPlanRequests.remove(planId);
    _optimisticPartyPlans.remove(planId);
    _saveCachedRequestsToPrefs();
  }

  static Future<void> _saveCachedRequestsToPrefs() async {
    try {
      final userId = currentUserId;
      if (userId == null || userId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _userPreferenceKey('cached_requested_plan_ids', userId),
        jsonEncode(_cachedRequestedPlanIds.toList()),
      );
    } catch (_) {}
  }

  /// Normalize any raw image path to a full URL, or return null if empty/invalid.
  static String? formatImageUrl(dynamic rawUrl) {
    if (rawUrl == null) return null;
    var url = rawUrl.toString().trim();
    if (url.isEmpty || url == 'null' || url == 'undefined') return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('assets/')) return url;
    while (url.startsWith('//')) {
      url = url.substring(1);
    }
    final clean = url.replaceAll('\\', '/');
    return '$baseUrl${clean.startsWith('/') ? clean : '/$clean'}';
  }

  static Future<void> initAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token');
    selectedCity = prefs.getString('selected_city');

    _ensureLocalStateForCurrentUser();
    final userId = currentUserId;
    final savedRequestedPlansJson = userId == null
        ? null
        : prefs.getString(
            _userPreferenceKey('cached_requested_plan_ids', userId),
          );
    if (savedRequestedPlansJson != null) {
      try {
        final List<dynamic> list = jsonDecode(savedRequestedPlansJson);
        for (final item in list) {
          if (item != null) {
            _cachedRequestedPlanIds.add(item.toString());
          }
        }
      } catch (_) {}
    }

    if (_authToken != null) {
      debugPrint('Loaded persisted auth token');
      initSocket();
      unawaited(SubscriptionProvider.instance.refresh());
    }
  }

  static socket_io.Socket? socket;
  static final Map<String, List<Function(dynamic)>> _socketListeners = {};

  static final StreamController<Map<String, dynamic>> _chatUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get chatUpdateStream =>
      _chatUpdateController.stream;

  static void notifyChatUpdated({
    required String conversationId,
    required String lastMessagePreview,
    String? lastMessageAt,
    String? messageId,
    bool deleted = false,
  }) {
    _chatUpdateController.add({
      'conversationId': conversationId,
      'lastMessagePreview': lastMessagePreview,
      'lastMessageAt': lastMessageAt,
      'messageId': messageId,
      'deleted': deleted,
    });
  }

  static void addSocketListener(String event, Function(dynamic) callback) {
    if (!_socketListeners.containsKey(event)) {
      _socketListeners[event] = [];
    }
    _socketListeners[event]!.add(callback);
    if (socket != null) {
      socket!.on(event, callback);
    }
  }

  static void removeSocketListener(String event, Function(dynamic) callback) {
    if (_socketListeners.containsKey(event)) {
      _socketListeners[event]!.remove(callback);
      if (socket != null) {
        socket!.off(event, callback);
      }
    }
  }

  static bool get isSocketConnected =>
      socket != null && socket!.connected == true;

  static void initSocket() {
    final userId = currentUserId;
    if (userId == null) return;
    _ensureLocalStateForCurrentUser();
    disconnectSocket();

    socket = socket_io.io(
      baseUrl,
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionAttempts(99999)
          .build(),
    );

    socket!.connect();

    socket!.onConnect((_) {
      debugPrint('Socket connected: ${socket!.id}');
      socket!.emit('join_user_room', userId);
      if (selectedCity != null && selectedCity!.isNotEmpty) {
        joinCityRoom(selectedCity!);
      }
      // Re-bind all registered listeners
      _socketListeners.forEach((event, callbacks) {
        for (final cb in callbacks) {
          socket!.on(event, cb);
        }
      });
      // Initialize or reconcile RealtimeSyncManager
      RealtimeSyncManager.instance.init();
      RealtimeSyncManager.instance.reconcileDelta();
    });

    socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
  }

  static void joinCityRoom(String city) {
    if (socket != null && socket!.connected && city.isNotEmpty) {
      socket!.emit('join_city_room', city);
    }
  }

  static void leaveCityRoom(String city) {
    if (socket != null && socket!.connected && city.isNotEmpty) {
      socket!.emit('leave_city_room', city);
    }
  }

  /// Fetch lightweight delta synchronization from server
  static Future<Map<String, dynamic>?> fetchDeltaSync(DateTime since) async {
    try {
      final isoSince = since.toUtc().toIso8601String();
      final res = await get('/api/mobile/sync/delta?since=$isoSince');
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[ApiService] fetchDeltaSync error: $e');
    }
    return null;
  }

  static void disconnectSocket() {
    if (socket != null) {
      socket!.disconnect();
      socket!.dispose();
      socket = null;
    }
  }

  static Future<void> setAuthToken(String? token) async {
    final previousUserId = currentUserId;
    disconnectSocket();
    _authToken = token;
    cachedCurrentUser = null;
    _ensureLocalStateForCurrentUser();
    final isNewSession = previousUserId != currentUserId;
    if (isNewSession) authSessionNotifier.value++;

    final prefs = await SharedPreferences.getInstance();
    if (token != null && token.trim().isNotEmpty) {
      await prefs.setString('auth_token', token.trim());
      await loadLocalReadIds();
      initSocket();
      unawaited(SubscriptionProvider.instance.refresh());
    } else {
      await prefs.remove('auth_token');
      disconnectSocket();
    }
  }

  static Future<void> clearAuthToken() async {
    final previousUserId = currentUserId;
    disconnectSocket();
    _authToken = null;
    cachedCurrentUser = null;
    selectedCity = null;
    _ensureLocalStateForCurrentUser();
    if (previousUserId != null) authSessionNotifier.value++;
    SubscriptionProvider.instance.reset();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('selected_city');
      // Remove obsolete device-wide keys. Account-scoped values are retained
      // and are only ever loaded for the matching authenticated account.
      await prefs.remove('cached_requested_plan_ids');
      await prefs.remove('localReadNotificationIds');
      await prefs.remove('localReadRequestIds');
      await prefs.remove('biometric_enabled');
    } catch (e) {
      debugPrint('Error clearing prefs during clearAuthToken: $e');
    }
  }

  static Future<void> logout() async {
    final userId = currentUserId;
    if (userId != null) {
      try {
        await post('/api/mobile/auth/logout', body: {'userId': userId});
      } catch (e) {
        debugPrint('Logout API failed: $e');
      }
    }
    try {
      await PushNotificationService.unregisterTokenOnLogout();
    } catch (e) {
      debugPrint('Error unregistering FCM token on logout: $e');
    }
    // Drop cached photos so the next account on this device never sees the
    // previous user's images.
    try {
      await LunaraImageCache.clearAll();
    } catch (e) {
      debugPrint('Error clearing image cache on logout: $e');
    }
    await clearAuthToken();
  }

  static Future<void> setSelectedCity(String city) async {
    selectedCity = city;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_city', city);
  }

  static String? get authToken => _authToken;

  static Future<User?> fetchProfile({
    String? userId,
    bool forceRefresh = false,
  }) async {
    try {
      if (_authToken == null) {
        await initAuthToken();
      }
      String? targetUserId = userId;
      if (targetUserId == 'undefined' ||
          targetUserId == 'null' ||
          (targetUserId != null && targetUserId.trim().isEmpty)) {
        targetUserId = null;
      }
      targetUserId ??= currentUserId ?? cachedCurrentUser?.id;

      final isSelf =
          targetUserId == null ||
          targetUserId == currentUserId ||
          (cachedCurrentUser != null && targetUserId == cachedCurrentUser!.id);
      if (isSelf &&
          !forceRefresh &&
          cachedCurrentUser != null &&
          _lastProfileFetchTime != null) {
        if (DateTime.now().difference(_lastProfileFetchTime!) <
            const Duration(seconds: 15)) {
          return cachedCurrentUser;
        }
      }

      final Map<String, String> queryParams = {};
      if (targetUserId != null &&
          targetUserId != 'undefined' &&
          targetUserId != 'null' &&
          targetUserId.trim().isNotEmpty) {
        queryParams['userId'] = targetUserId;
      }

      final response = await get(
        '/api/mobile/user/userprofile',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final user = User.fromJson(data);
          if (isSelf) {
            cachedCurrentUser = user;
            _lastProfileFetchTime = DateTime.now();
          }
          return user;
        }
      }
      return cachedCurrentUser;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return cachedCurrentUser;
    }
  }

  static int calculateMatchPercentage(dynamic otherUser) {
    if (cachedCurrentUser == null) {
      // Consistent fallback based on other user's ID to keep UI stable
      int idHash = 0;
      if (otherUser is Map) {
        idHash = (otherUser['id'] ?? otherUser['_id'] ?? '')
            .toString()
            .hashCode
            .abs();
      } else if (otherUser is User) {
        idHash = otherUser.id.hashCode.abs();
      }
      return 60 + (idHash % 36);
    }

    User? other;
    if (otherUser is Map<String, dynamic>) {
      try {
        other = User.fromJson(otherUser);
      } catch (_) {}
    } else if (otherUser is User) {
      other = otherUser;
    } else if (otherUser is Map) {
      try {
        other = User.fromJson(Map<String, dynamic>.from(otherUser));
      } catch (_) {}
    }

    if (other == null) {
      return 75; // generic fallback
    }

    // Don't compare user with themselves
    if (other.id == cachedCurrentUser!.id) {
      return 100;
    }

    return cachedCurrentUser!.calculateMatchWith(other);
  }

  static Future<List<Venue>> fetchVenues({
    String? city,
    bool forceRefresh = false,
  }) async {
    final targetCity = (city ?? selectedCity ?? '').trim();
    final cacheKey = targetCity.toLowerCase();
    final now = DateTime.now();

    if (!forceRefresh && _cachedVenuesByCity.containsKey(cacheKey)) {
      final cacheTime = _venuesCacheTimestamps[cacheKey];
      if (cacheTime != null && now.difference(cacheTime).inSeconds < 60) {
        return _cachedVenuesByCity[cacheKey]!;
      }
    }

    try {
      final path = targetCity.isNotEmpty
          ? '/api/venues?city=${Uri.encodeComponent(targetCity)}'
          : '/api/venues';
      final response = await get(path);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['venues'] != null) {
          final list = (data['venues'] as List)
              .map((json) => Venue.fromJson(json))
              .toList();
          if (list.isNotEmpty) {
            _cachedVenuesByCity[cacheKey] = list;
            _venuesCacheTimestamps[cacheKey] = DateTime.now();
            return list;
          }
        }
      }
      // Fallback: if we queried a specific city and got no venues, try fetching all venues
      if (targetCity.isNotEmpty) {
        final fallbackResponse = await get('/api/venues');
        if (fallbackResponse.statusCode == 200) {
          final data = jsonDecode(fallbackResponse.body);
          if (data['success'] == true && data['venues'] != null) {
            final list = (data['venues'] as List)
                .map((json) => Venue.fromJson(json))
                .toList();
            if (list.isNotEmpty) {
              _cachedVenuesByCity[cacheKey] = list;
              _venuesCacheTimestamps[cacheKey] = DateTime.now();
              return list;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching venues: $e');
    }
    if (_cachedVenuesByCity.containsKey(cacheKey)) {
      return _cachedVenuesByCity[cacheKey]!;
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchActiveAds({
    String? city,
    String? type,
    bool forceRefresh = false,
  }) async {
    final targetCity = city ?? selectedCity ?? '';
    final cacheKey = '${targetCity.toLowerCase()}_${type ?? 'all'}';
    final now = DateTime.now();

    if (!forceRefresh && _cachedAds.containsKey(cacheKey)) {
      final cacheTime = _adsCacheTimestamps[cacheKey];
      if (cacheTime != null && now.difference(cacheTime).inSeconds < 60) {
        return _cachedAds[cacheKey]!;
      }
    }

    try {
      final queryParams = <String>[];
      if (targetCity.isNotEmpty) {
        queryParams.add('city=${Uri.encodeComponent(targetCity)}');
      }
      if (type != null && type.isNotEmpty) {
        queryParams.add('type=${Uri.encodeComponent(type)}');
      }
      final queryString = queryParams.isNotEmpty
          ? '?${queryParams.join('&')}'
          : '';
      final path = '/api/ads/active$queryString';
      final response = await get(path);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final list = List<Map<String, dynamic>>.from(data['data']);
          _cachedAds[cacheKey] = list;
          _adsCacheTimestamps[cacheKey] = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('Error fetching active ads: $e');
    }
    if (_cachedAds.containsKey(cacheKey)) {
      return _cachedAds[cacheKey]!;
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchCustomers({
    String? city,
    int limit = 500,
    int page = 1,
    bool includeAllCities = true,
    bool forceRefresh = false,
    String? search,
  }) async {
    final targetCity = includeAllCities ? 'all' : (city ?? selectedCity ?? '');
    final cacheKey =
        '${targetCity.toLowerCase()}_${limit}_${page}_${includeAllCities}_${search ?? ''}';
    final now = DateTime.now();

    if (!forceRefresh && _cachedCustomers.containsKey(cacheKey)) {
      final cacheTime = _customersCacheTimestamps[cacheKey];
      if (cacheTime != null && now.difference(cacheTime).inSeconds < 60) {
        return _cachedCustomers[cacheKey]!;
      }
    }

    try {
      final userId = currentUserId;
      final Map<String, String> params = {
        'limit': limit.toString(),
        'page': page.toString(),
      };
      if (userId != null) params['currentUserId'] = userId;
      if (forceRefresh) params['refresh'] = 'true';
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (includeAllCities) {
        params['allCities'] = 'true';
      } else {
        final String? cityToFilter = city ?? selectedCity;
        if (cityToFilter != null && cityToFilter.isNotEmpty) {
          params['city'] = cityToFilter;
        }
      }
      final response = await get(
        '/api/mobile/user/customers',
        queryParameters: params.isNotEmpty ? params : null,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dynamic list = data['customers'] ?? data['data'];
        if (list != null && list is List) {
          final result = List<Map<String, dynamic>>.from(
            list.where((item) => item is Map && item['id'] != null),
          );
          for (final item in result) {
            final uid = item['id']?.toString();
            final tier = (item['subscriptionTier'] ??
                    item['tier'] ??
                    item['packageTier'] ??
                    item['planTier'] ??
                    item['vipTier'])
                ?.toString();
            registerUserTier(uid, tier);
          }
          _cachedCustomers[cacheKey] = result;
          _customersCacheTimestamps[cacheKey] = DateTime.now();
          return result;
        } else if (data is List) {
          final result = List<Map<String, dynamic>>.from(
            data.where((item) => item is Map && item['id'] != null),
          );
          for (final item in result) {
            final uid = item['id']?.toString();
            final tier = (item['subscriptionTier'] ??
                    item['tier'] ??
                    item['packageTier'] ??
                    item['planTier'] ??
                    item['vipTier'])
                ?.toString();
            registerUserTier(uid, tier);
          }
          _cachedCustomers[cacheKey] = result;
          _customersCacheTimestamps[cacheKey] = DateTime.now();
          return result;
        }
      }
    } catch (e) {
      debugPrint('Error fetching customers: $e');
    }
    if (_cachedCustomers.containsKey(cacheKey)) {
      return _cachedCustomers[cacheKey]!;
    }
    return [];
  }

  static Future<List<Package>> fetchVenuePackages(
    String venueId, {
    bool forceRefresh = false,
  }) async {
    if (venueId.isEmpty) return [];
    final now = DateTime.now();

    if (!forceRefresh && _cachedPackagesByVenue.containsKey(venueId)) {
      final cacheTime = _packagesCacheTimestamps[venueId];
      if (cacheTime != null && now.difference(cacheTime).inSeconds < 60) {
        return _cachedPackagesByVenue[venueId]!;
      }
    }

    try {
      final response = await get(
        '/api/mobile/bookings/venues/$venueId/packages',
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final dynamic packageList =
            jsonResponse['data'] ?? jsonResponse['packages'];

        if (packageList is List) {
          final list = packageList
              .map((json) => Package.fromJson(json))
              .toList();
          _cachedPackagesByVenue[venueId] = list;
          _packagesCacheTimestamps[venueId] = DateTime.now();
          return list;
        } else if (jsonResponse is List) {
          final list = jsonResponse
              .map((json) => Package.fromJson(json))
              .toList();
          _cachedPackagesByVenue[venueId] = list;
          _packagesCacheTimestamps[venueId] = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('Error fetching venue packages: $e');
    }
    if (_cachedPackagesByVenue.containsKey(venueId)) {
      return _cachedPackagesByVenue[venueId]!;
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchPartyPlans({
    int page = 1,
    int limit = 20,
    String status = 'active',
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${status}_${page}_$limit';
    final now = DateTime.now();

    if (!forceRefresh && _cachedPartyPlans.containsKey(cacheKey)) {
      final cacheTime = _partyPlansCacheTimestamps[cacheKey];
      if (cacheTime != null && now.difference(cacheTime).inSeconds < 45) {
        return _cachedPartyPlans[cacheKey]!;
      }
    }

    try {
      final query = {
        'status': status,
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (currentUserId != null) {
        query['requesterId'] = currentUserId!;
      }
      final response = await get(
        '/api/mobile/party-plans',
        queryParameters: query,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final list = List<Map<String, dynamic>>.from(data['data']);
          _cachedPartyPlans[cacheKey] = list;
          _partyPlansCacheTimestamps[cacheKey] = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('Error fetching party plans: $e');
    }
    if (_cachedPartyPlans.containsKey(cacheKey)) {
      return _cachedPartyPlans[cacheKey]!;
    }
    return [];
  }

  static Future<bool> submitLargePartyRequest({
    required String venueId,
    required String date,
    required String time,
    required int guests,
    required String subject,
    required String requirement,
    required String description,
    required String mobileNumber,
    String? optionalMobileNumber,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await post(
        '/api/mobile/bookings',
        timeout: transactionalTimeout,
        body: {
          'userId': userId,
          'venueId': venueId,
          'bookingDate': date,
          'startTime': time,
          'tablePackage': 'none',
          'goingMode': 'party_request',
          'numberOfGuests': guests,
          'partySubject': subject,
          'partyRequirement': requirement,
          'partyDescription': description,
          'mobileNumber': mobileNumber.trim(),
          if (optionalMobileNumber != null &&
              optionalMobileNumber.trim().isNotEmpty)
            'optionalMobileNumber': optionalMobileNumber.trim(),
        },
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        try {
          final data = jsonDecode(response.body);
          final msg =
              data['message'] ?? data['error'] ?? 'Failed to submit request';
          throw Exception(msg);
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('Failed to submit request');
        }
      }
    } catch (e) {
      debugPrint('submitLargePartyRequest error: $e');
      rethrow;
    }
  }

  static Future<List<dynamic>?>? _inFlightBookings;
  static DateTime? _bookingsCacheTime;
  static List<dynamic>? _cachedBookings;

  static Future<List<dynamic>?> fetchBookings({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedBookings != null &&
        _bookingsCacheTime != null &&
        now.difference(_bookingsCacheTime!).inSeconds < 30) {
      return _cachedBookings;
    }

    if (_inFlightBookings != null) {
      return _inFlightBookings;
    }

    _inFlightBookings = () async {
      try {
        final response = await get(
          '/api/mobile/bookings',
          queryParameters: {'userId': userId},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            _cachedBookings = data['data'] as List<dynamic>;
            _bookingsCacheTime = DateTime.now();
            return _cachedBookings;
          }
        }
      } catch (e) {
        debugPrint('fetchBookings error: $e');
      } finally {
        _inFlightBookings = null;
      }
      return _cachedBookings;
    }();

    return _inFlightBookings;
  }

  /// Fetches only the current user's large-party (group party) booking requests.
  /// Returns them as a typed list sorted newest-first.
  static Future<List<Map<String, dynamic>>> fetchMyLargePartyBookings({
    bool forceRefresh = false,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) return [];

      // 1. Fetch normal large party request bookings
      final List<Map<String, dynamic>> bookingParties = [];
      final raw = await fetchBookings(forceRefresh: forceRefresh);
      if (raw != null) {
        bookingParties.addAll(
          raw
              .whereType<Map>()
              .where((b) {
                final gm = b['goingMode']?.toString();
                if (gm != 'party_request' || gm == 'plan') {
                  return false;
                }
                final spec = b['specialRequests']?.toString() ?? '';
                if (spec.contains('"joinerId"') || spec.contains('"planId"')) {
                  return false;
                }
                return true;
              })
              .map((b) => Map<String, dynamic>.from(b)),
        );
      }

      // 2. Fetch group parties (<= 20 friends)
      //
      // Cached on the same 30s window as bookings: without this the live feed
      // hit this endpoint on every single refresh, cached or not.
      List<Map<String, dynamic>> groupParties = [];
      final gpNow = DateTime.now();
      if (!forceRefresh &&
          _cachedGroupParties != null &&
          _groupPartiesCacheTime != null &&
          gpNow.difference(_groupPartiesCacheTime!).inSeconds < 30) {
        groupParties = _cachedGroupParties!;
      } else {
        try {
          final response = await get(
            '/api/mobile/group-parties',
            queryParameters: {'userId': userId},
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true && data['data'] != null) {
              final List rawList = data['data'];
              for (final gp in rawList) {
                if (gp is Map) {
                  final totalCount =
                      (gp['numberOfFriends'] ?? gp['totalParticipants'] ?? 5)
                          is int
                      ? (gp['numberOfFriends'] ?? gp['totalParticipants'] ?? 5)
                      : (int.tryParse(
                              (gp['numberOfFriends'] ??
                                      gp['totalParticipants'] ??
                                      5)
                                  .toString(),
                            ) ??
                            5);
                  final hostUser = gp['user'] ?? gp['host'];
                  groupParties.add({
                    'id': gp['id'],
                    'bookingId': gp['id'],
                    'venue': gp['venue'],
                    'venueName': gp['venue']?['name'],
                    'venueAddress':
                        gp['venue']?['addressLine1'] ??
                        gp['venue']?['city'] ??
                        '',
                    'status': gp['status']?.toString() ?? 'pending',
                    'bookingStatus': gp['status']?.toString() ?? 'pending',
                    'paymentStatus': gp['paymentStatus']?.toString(),
                    'adminApprovalStatus': gp['adminApprovalStatus']
                        ?.toString(),
                    'numberOfGuests': totalCount,
                    'numberOfFriends': totalCount,
                    'totalParticipants': totalCount,
                    'memberCount': totalCount > 1 ? totalCount - 1 : 1,
                    'hostCount': 1,
                    'partySubject': 'Group Party',
                    'bookingDate': gp['partyDate'],
                    'partyDate': gp['partyDate'],
                    'startTime':
                        (gp['startTime'] != null &&
                            gp['startTime'].toString().trim().isNotEmpty)
                        ? gp['startTime'].toString().trim()
                        : '08:00 PM',
                    'approvedAmount': gp['totalAmount'],
                    'charges': gp['totalAmount'],
                    'totalAmount': gp['totalAmount'],
                    'host': hostUser,
                    'user': hostUser,
                    'createdAt': gp['createdAt'],
                    'mobileNumber': gp['mobileNumber'],
                    'optionalMobileNumber': gp['optionalMobileNumber'],
                    'goingMode': 'party_request',
                    'ticketCode': gp['ticketCode'],
                    'ticketUrl': gp['ticketUrl'],
                    'isSmallGroupParty': true,
                  });
                }
              }
              // Only a genuinely successful read is worth caching — a transient
              // failure must not pin an empty list for the next 30 seconds.
              _cachedGroupParties = groupParties;
              _groupPartiesCacheTime = DateTime.now();
            }
          }
        } catch (gpErr) {
          debugPrint(
            'fetchMyGroupParties in fetchMyLargePartyBookings error: $gpErr',
          );
        }
        if (groupParties.isEmpty && _groupPartiesCacheTime == null) {
          // Nothing fetched and nothing cached: fall back to the last known
          // list rather than dropping group parties out of the feed.
          groupParties = _cachedGroupParties ?? groupParties;
        }
      }

      // Combine both
      final List<Map<String, dynamic>> combined = [
        ...bookingParties,
        ...groupParties,
      ];

      // Sort newest-first by createdAt
      combined.sort((a, b) {
        final da =
            DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(0);
        final db =
            DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });

      return combined;
    } catch (e) {
      debugPrint('fetchMyLargePartyBookings error: $e');
      return [];
    }
  }

  static List<Map<String, dynamic>>? _cachedTickets;
  static DateTime? _ticketsCacheTime;
  static Future<List<Map<String, dynamic>>>? _inFlightTickets;

  /// Fetches ALL tickets for current user across standard bookings, group parties (<= 20), and confirmed party plans.
  /// Reads directly from the backend `Ticket` table (`GET /api/mobile/tickets`)
  /// — the actual source of truth every real ticket-generation helper writes to.
  static Future<List<Map<String, dynamic>>> fetchAllUserTickets({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedTickets != null &&
        _ticketsCacheTime != null &&
        now.difference(_ticketsCacheTime!).inSeconds < 30) {
      return _cachedTickets!;
    }

    if (_inFlightTickets != null) {
      return _inFlightTickets!;
    }

    _inFlightTickets = _doFetchAllUserTickets(userId);
    return _inFlightTickets!;
  }

  static Future<List<Map<String, dynamic>>> _doFetchAllUserTickets(
    String userId,
  ) async {
    try {
      final response = await get(
        '/api/mobile/tickets',
        queryParameters: {'tab': 'all', 'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final list = List<Map<String, dynamic>>.from(data['data']);
          _cachedTickets = list;
          _ticketsCacheTime = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('fetchAllUserTickets error: $e');
    } finally {
      _inFlightTickets = null;
    }

    // If we have cached tickets from a previous successful load, serve them on transient network drop
    if (_cachedTickets != null) return _cachedTickets!;

    // Resilient fallback to fetchBookings ONLY if network/API failed
    try {
      final bookings = await fetchBookings(forceRefresh: true);
      if (bookings != null && bookings.isNotEmpty) {
        return bookings
            .whereType<Map>()
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
      }
    } catch (e) {
      debugPrint('fetchAllUserTickets fallback error: $e');
    }

    return <Map<String, dynamic>>[];
  }

  static Future<Map<String, dynamic>?> swipeUser({
    required String targetUserId,
    required String action,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) return null;

      final response = await post(
        '/api/mobile/user/swipe',
        body: {
          'userId': userId,
          'targetUserId': targetUserId,
          'action': action,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      } else if (response.statusCode == 403) {
        // Subscription limit reached or feature not available
        final data = jsonDecode(response.body);
        return {
          'limitReached': true,
          'code': data['code'] ?? 'LIMIT_REACHED',
          'message': data['message'] ?? 'Upgrade to Lunara VIP to continue.',
          'action': action,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error swiping user: $e');
      return null;
    }
  }

  static Future<bool> unlikeUser({required String targetUserId}) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;

      final response = await post(
        '/api/mobile/user/unlike',
        body: {'userId': userId, 'targetUserId': targetUserId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error unliking user: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchReliabilityHistory() async {
    try {
      final response = await get('/api/mobile/user/reliability-history');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data']?['history'] != null) {
          return List<Map<String, dynamic>>.from(data['data']['history']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching reliability history: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> activateProfileBoost() async {
    try {
      final response = await post('/api/mobile/subscriptions/use-boost');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      debugPrint('Error activating profile boost: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMyLikesAndMatches() async {
    try {
      if (currentUserId == null) {
        await fetchProfile();
      }
      final userId = currentUserId;
      if (userId == null) return [];

      final response = await get(
        '/api/mobile/user/likes-matches',
        queryParameters: {'userId': userId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching likes and matches: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> fetchWhoLikedSummary() async {
    try {
      if (currentUserId == null) {
        await fetchProfile();
      }
      final userId = currentUserId;
      if (userId == null) return null;

      final response = await get(
        '/api/mobile/user/who-liked-summary',
        queryParameters: {'userId': userId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final resData = Map<String, dynamic>.from(data['data']);
          resData['totalCount'] = resData['totalCount'] ?? resData['count'] ?? 0;
          resData['superlikesCount'] = resData['superlikesCount'] ?? 0;
          resData['locked'] = resData['locked'] ?? (resData['canSeeWhoLiked'] == false);
          return resData;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching who liked summary: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> fetchPeopleWhoLikedMe({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      if (currentUserId == null) {
        await fetchProfile();
      }
      final userId = currentUserId;
      if (userId == null) {
        return {'users': [], 'pagination': {}, 'locked': false};
      }

      final response = await get(
        '/api/mobile/user/who-liked-me',
        queryParameters: {
          'userId': userId,
          'page': page.toString(),
          'limit': limit.toString(),
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final dynamic rawList = data['data'] ?? data['users'];
          final users = rawList is List
              ? List<Map<String, dynamic>>.from(rawList.whereType<Map>())
              : <Map<String, dynamic>>[];
          final pagination = data['pagination'] is Map
              ? Map<String, dynamic>.from(data['pagination'])
              : <String, dynamic>{};
          final isLocked = data['locked'] == true;
          return {
            'users': users,
            'pagination': pagination,
            'locked': isLocked,
            'canSeeWhoLiked': data['canSeeWhoLiked'] ?? !isLocked,
          };
        }
      } else if (response.statusCode == 403) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'VIP_REQUIRED' || data['success'] == false) {
          return {'users': [], 'pagination': {}, 'locked': true};
        }
      }
      return {'users': [], 'pagination': {}, 'locked': false};
    } catch (e) {
      debugPrint('Error fetching people who liked me: $e');
      return {'users': [], 'pagination': {}, 'locked': false};
    }
  }

  static Future<List<Map<String, dynamic>>> fetchStrangersMeetFeed({
    int page = 1,
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${page}_$limit';
    final now = DateTime.now();

    if (!forceRefresh && _cachedStrangersMeetFeed.containsKey(cacheKey)) {
      final cacheTime = _strangersMeetFeedCacheTimestamps[cacheKey];
      if (cacheTime != null && now.difference(cacheTime).inSeconds < 45) {
        return _cachedStrangersMeetFeed[cacheKey]!;
      }
    }

    try {
      final response = await get(
        '/api/mobile/strangers-meet/feed',
        queryParameters: {'page': page.toString(), 'limit': limit.toString()},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final list = List<Map<String, dynamic>>.from(data['data']);
          _cachedStrangersMeetFeed[cacheKey] = list;
          _strangersMeetFeedCacheTimestamps[cacheKey] = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('Error fetching strangers meet feed: $e');
    }
    if (_cachedStrangersMeetFeed.containsKey(cacheKey)) {
      return _cachedStrangersMeetFeed[cacheKey]!;
    }
    return [];
  }
  // â”€â”€â”€ City APIs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<List<String>> fetchCities() async {
    try {
      final response = await get('/api/mobile/cities');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<String>.from(
            (data['data'] as List).map((c) => c['name']?.toString() ?? ''),
          );
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching cities: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> fetchLiveFeedData({
    String? venueId,
    String? date,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        venueId == null &&
        date == null &&
        _cachedLiveFeedData != null &&
        _liveFeedCacheTime != null) {
      if (now.difference(_liveFeedCacheTime!).inSeconds < 5) {
        return _cachedLiveFeedData!;
      }
    }

    try {
      final queryParams = <String, String>{};
      if (venueId != null) queryParams['venueId'] = venueId;
      if (date != null) queryParams['date'] = date;
      if (currentUserId != null) queryParams['viewerId'] = currentUserId!;

      final response = await get(
        '/api/mobile/plans/live-feed',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final myReqs = List<Map<String, dynamic>>.from(
            data['myRequests'] ?? [],
          );
          for (final req in myReqs) {
            final pId =
                req['partyPlanId']?.toString() ??
                req['planId']?.toString() ??
                req['plan']?['id']?.toString();
            final reqStatus =
                (req['status'] ?? req['joinerPaymentStatus'] ?? 'pending')
                    .toString()
                    .toLowerCase();
            if (pId != null &&
                pId.isNotEmpty &&
                reqStatus != 'cancelled' &&
                reqStatus != 'rejected') {
              markPartyPlanAsRequestedLocal(pId, req);
            }
          }
          final feedList = List<Map<String, dynamic>>.from(data['data'] ?? []);
          final Set<String> existingPlanIds = {};
          for (final f in feedList) {
            final pid = (f['id'] ?? f['planId'] ?? f['partyPlanId'])
                ?.toString();
            if (pid != null) existingPlanIds.add(pid);
          }
          for (final r in myReqs) {
            final pid =
                (r['partyPlanId'] ?? r['planId'] ?? r['id'] ?? r['plan']?['id'])
                    ?.toString();
            if (pid != null) existingPlanIds.add(pid);
          }
          _optimisticPartyPlans.forEach((optId, optPlan) {
            if (!existingPlanIds.contains(optId)) {
              feedList.insert(0, optPlan);
            }
          });

          final result = {
            'feed': feedList,
            'myRequests': myReqs,
            'incomingRequests': List<Map<String, dynamic>>.from(
              data['incomingRequests'] ?? [],
            ),
            'pendingPayments': List<Map<String, dynamic>>.from(
              data['pendingPayments'] ?? [],
            ),
          };
          if (venueId == null && date == null) {
            _cachedLiveFeedData = result;
            _liveFeedCacheTime = DateTime.now();
          }
          return result;
        }
      }
    } catch (e) {
      debugPrint('Error fetching live feed: $e');
    }
    if (venueId == null && date == null && _cachedLiveFeedData != null) {
      return _cachedLiveFeedData!;
    }
    final fallbackFeed = <Map<String, dynamic>>[];
    _optimisticPartyPlans.forEach((_, optPlan) => fallbackFeed.add(optPlan));
    return {
      'feed': fallbackFeed,
      'myRequests': [],
      'incomingRequests': [],
      'pendingPayments': [],
    };
  }

  static Future<PartyPlanRequestResult> requestToJoinPartyPlanDetailed(
    String planId,
  ) async {
    final userId = currentUserId;
    if (userId == null) {
      return PartyPlanRequestResult(
        success: false,
        alreadyRequested: false,
        isNewRequest: false,
        message: 'User not logged in.',
      );
    }
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/requests',
        body: {'userId': userId},
      );
      if (response.statusCode == 201) {
        Map<String, dynamic>? requestData;
        try {
          final payload = jsonDecode(response.body);
          if (payload is Map && payload['data'] is Map) {
            requestData = Map<String, dynamic>.from(payload['data'] as Map);
          }
        } catch (_) {}
        markPartyPlanAsRequestedLocal(planId, requestData);
        notifyFeedNeedsRefresh();
        return PartyPlanRequestResult(
          success: true,
          alreadyRequested: true,
          isNewRequest: true,
          message: 'Request sent successfully!',
          requestId: requestData?['id']?.toString(),
          status: requestData?['status']?.toString().toLowerCase() ?? 'pending',
        );
      }

      String msg = 'Failed to send request.';
      Map<String, dynamic>? rawResponseData;
      try {
        final data = jsonDecode(response.body);
        if (data is Map) {
          rawResponseData = Map<String, dynamic>.from(data);
          if (data['message'] != null) {
            msg = data['message'].toString();
          }
        }
      } catch (_) {}

      final msgLower = msg.toLowerCase();
      if (msgLower.contains('already requested') ||
          msgLower.contains('already has an accepted') ||
          msgLower.contains('already pending')) {
        markPartyPlanAsRequestedLocal(planId);
        return PartyPlanRequestResult(
          success: true,
          alreadyRequested: true,
          isNewRequest: false,
          message: msg,
          rawData: rawResponseData,
        );
      }

      return PartyPlanRequestResult(
        success: false,
        alreadyRequested: false,
        isNewRequest: false,
        message: msg,
        rawData: rawResponseData,
      );
    } catch (e) {
      debugPrint('requestToJoinPartyPlan error: $e');
      return PartyPlanRequestResult(
        success: false,
        alreadyRequested: false,
        isNewRequest: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<bool> requestToJoinPartyPlan(String planId) async {
    final res = await requestToJoinPartyPlanDetailed(planId);
    return res.success;
  }

  static Future<List<Map<String, dynamic>>> fetchPartyPlanRequests(
    String planId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final response = await get(
        '/api/mobile/party-plans/$planId/requests',
        queryParameters: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchPartyPlanRequests error: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchMyPartyPlanRequests() async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final response = await get(
        '/api/mobile/party-plans/requests/user/$userId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final list = List<Map<String, dynamic>>.from(data['data']);
          for (final req in list) {
            final pId =
                req['partyPlanId']?.toString() ??
                req['planId']?.toString() ??
                req['plan']?['id']?.toString();
            final reqStatus =
                (req['status'] ?? req['joinerPaymentStatus'] ?? 'pending')
                    .toString()
                    .toLowerCase();
            if (pId != null &&
                pId.isNotEmpty &&
                reqStatus != 'cancelled' &&
                reqStatus != 'rejected') {
              markPartyPlanAsRequestedLocal(pId, req);
            }
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('fetchMyPartyPlanRequests error: $e');
    }
    if (_cachedPartyPlanRequests.isNotEmpty) {
      return _cachedPartyPlanRequests.values.toList();
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchMyPartyPlans() async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final response = await get('/api/mobile/party-plans/user/$userId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchMyPartyPlans error: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchUserPartyPlans(
    String userId,
  ) async {
    try {
      final response = await get('/api/mobile/party-plans/user/$userId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchUserPartyPlans error: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchUserStrangersMeets(
    String userId,
  ) async {
    try {
      final response = await get('/api/mobile/strangers-meet/user/$userId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchUserStrangersMeets error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> acceptPartyPlanRequest(
    String rawReqId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final reqId = cleanBookingId(rawReqId);
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/accept',
        body: {'userId': userId},
        timeout: transactionalTimeout,
      );
      if (response.body.isNotEmpty) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) {
            if (response.statusCode == 200) {
              notifyFeedNeedsRefresh();
              return data['data'] is Map<String, dynamic> ? data['data'] : data;
            }
            return data;
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('acceptPartyPlanRequest error: $e');
    }
    return null;
  }

  /// Loads the authoritative Party Plan data used when opening a notification
  /// or push deep link, where the original payload only contains a plan ID.
  static Future<Map<String, dynamic>?> fetchPartyPlanDetail(
    String rawPlanId,
  ) async {
    final planId = cleanBookingId(rawPlanId);
    if (planId.isEmpty) return null;
    try {
      final response = await get('/api/mobile/party-plans/$planId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['success'] == true && data['data'] is Map) {
          return Map<String, dynamic>.from(data['data'] as Map);
        }
      }
    } catch (e) {
      debugPrint('fetchPartyPlanDetail error: $e');
    }
    return null;
  }

  /// Cancels only the caller's unaccepted Party Plan request.
  static Future<bool> cancelPartyPlanRequest(
    String rawReqId, {
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final reqId = cleanBookingId(rawReqId);
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/cancel',
        body: {'userId': userId, 'reason': ?reason},
      );
      if (response.statusCode == 200) {
        String? targetPlanId;
        _cachedPartyPlanRequests.forEach((pId, req) {
          if (cleanBookingId(req['id']?.toString() ?? '') == reqId) {
            targetPlanId = pId;
          }
        });
        if (targetPlanId != null) {
          markPartyPlanAsCancelledLocal(targetPlanId!);
        }
        notifyFeedNeedsRefresh();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('cancelPartyPlanRequest error: $e');
      return false;
    }
  }

  /// Withdraws the caller's accepted request before their payment completes.
  static Future<bool> withdrawPartyPlanRequest(
    String rawReqId, {
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final reqId = cleanBookingId(rawReqId);
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/withdraw',
        body: {'userId': userId, 'reason': ?reason},
      );
      if (response.statusCode == 200) {
        String? targetPlanId;
        _cachedPartyPlanRequests.forEach((pId, req) {
          if (cleanBookingId(req['id']?.toString() ?? '') == reqId) {
            targetPlanId = pId;
          }
        });
        if (targetPlanId != null) {
          markPartyPlanAsCancelledLocal(targetPlanId!);
        }
        notifyFeedNeedsRefresh();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('withdrawPartyPlanRequest error: $e');
      return false;
    }
  }

  /// Host-only: withdraws an acceptance while the participant remains unpaid.
  static Future<bool> revokePartyPlanAcceptance(
    String rawReqId, {
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final reqId = cleanBookingId(rawReqId);
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/revoke',
        body: {'userId': userId, 'reason': ?reason},
      );
      if (response.statusCode == 200) {
        notifyFeedNeedsRefresh();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('revokePartyPlanAcceptance error: $e');
      return false;
    }
  }

  static Future<bool> confirmSelfPaidJoin(String reqId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/confirm-self-paid',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        notifyFeedNeedsRefresh();
        return true;
      }
    } catch (e) {
      debugPrint('confirmSelfPaidJoin error: $e');
    }
    return false;
  }

  static Future<bool> verifyJoinerPayment(
    String reqId,
    String orderId,
    String paymentId,
    String signature,
  ) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/joiner-pay',
        body: {
          'userId': userId,
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
      );
      if (response.statusCode == 200) {
        notifyFeedNeedsRefresh();
        return true;
      }
    } catch (e) {
      debugPrint('verifyJoinerPayment error: $e');
    }
    return false;
  }

  static Future<bool> verifyHostPayment(
    String planId,
    String orderId,
    String paymentId,
    String signature,
  ) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/host-pay',
        body: {
          'userId': userId,
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
      );
      if (response.statusCode == 200) {
        notifyFeedNeedsRefresh();
        return true;
      }
    } catch (e) {
      debugPrint('verifyHostPayment error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> cancelPartyPlanDetailed(
    String planId, {
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not authenticated'};
    }
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/cancel',
        body: {'userId': userId, 'reason': ?reason},
      );
      markPartyPlanAsCancelledLocal(planId);
      notifyFeedNeedsRefresh();
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic>
          ? data
          : {'success': response.statusCode == 200};
    } catch (e) {
      debugPrint('cancelPartyPlan error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<bool> cancelPartyPlan(String planId, {String? reason}) async {
    final res = await cancelPartyPlanDetailed(planId, reason: reason);
    return res?['success'] == true;
  }

  static Future<Map<String, dynamic>?> repostPartyPlan(
    String planId, {
    required DateTime newDateTime,
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not authenticated'};
    }
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/repost',
        body: {
          'userId': userId,
          'newDateTime': newDateTime.toUtc().toIso8601String(),
          'reason': ?reason,
        },
      );
      markPartyPlanAsCancelledLocal(planId);
      notifyFeedNeedsRefresh();
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic>
          ? data
          : {'success': response.statusCode == 200};
    } catch (e) {
      debugPrint('repostPartyPlan error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> makePartyPlanPublic(
    String planId,
  ) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not authenticated'};
    }
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/make-public',
        body: {'userId': userId},
      );
      notifyFeedNeedsRefresh();
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic>
          ? data
          : {'success': response.statusCode == 200};
    } catch (e) {
      debugPrint('makePartyPlanPublic error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> fetchWalletBalance({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedWalletBalance != null &&
        _walletBalanceCacheTime != null) {
      if (now.difference(_walletBalanceCacheTime!).inSeconds < 10) {
        return _cachedWalletBalance;
      }
    }

    try {
      final response = await get(
        '/api/mobile/wallet/balance',
        queryParameters: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          _cachedWalletBalance = Map<String, dynamic>.from(data['data']);
          _walletBalanceCacheTime = DateTime.now();
          return _cachedWalletBalance;
        }
      }
    } catch (e) {
      debugPrint('fetchWalletBalance error: $e');
    }
    return _cachedWalletBalance;
  }

  static Future<Map<String, dynamic>?> fetchWalletData({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedWalletData != null &&
        _walletDataCacheTime != null) {
      if (now.difference(_walletDataCacheTime!).inSeconds < 10) {
        return _cachedWalletData;
      }
    }

    try {
      final response = await get(
        '/api/mobile/wallet',
        queryParameters: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          _cachedWalletData = Map<String, dynamic>.from(data['data']);
          _walletDataCacheTime = DateTime.now();
          return _cachedWalletData;
        }
      }
    } catch (e) {
      debugPrint('fetchWalletData error: $e');
    }
    return _cachedWalletData;
  }

  static Future<Map<String, dynamic>?> createWalletRechargeOrder(
    double amount,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/wallet/recharge-order',
        body: {'userId': userId, 'amount': amount},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data['data'];
      }
    } catch (e) {
      debugPrint('createWalletRechargeOrder error: $e');
    }
    return null;
  }

  static Future<bool> verifyWalletRecharge({
    required double amount,
    required String razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/wallet/verify-recharge',
        body: {
          'userId': userId,
          'amount': amount,
          'razorpayPaymentId': razorpayPaymentId,
          'razorpayOrderId': razorpayOrderId,
          'razorpaySignature': razorpaySignature,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('verifyWalletRecharge error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> payVipWithWallet({
    required String packageId,
    required String tier,
    required double price,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/wallet/pay-vip',
        body: {
          'userId': userId,
          'packageId': packageId,
          'tier': tier,
          'price': price,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data;
      }
    } catch (e) {
      debugPrint('payVipWithWallet error: $e');
    }
    return null;
  }

  static String cleanBookingId(String rawId) {
    final uuidRegex = RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    );
    final match = uuidRegex.firstMatch(rawId);
    if (match != null) {
      return match.group(0)!;
    }
    return rawId
        .replaceAll('venue_booking_timeline_', '')
        .replaceAll('group_party_timeline_', '')
        .replaceAll('large_party_timeline_', '')
        .replaceAll('solo_booking_', '')
        .replaceAll('party_plan_timeline_', '')
        .replaceAll('notification_', '')
        .replaceAll('notif_', '')
        .replaceAll('venue_booking_', '')
        .replaceAll('group_party_', '')
        .replaceAll('large_party_', '')
        .replaceAll('party_plan_', '')
        .replaceAll('booking_', '')
        .replaceAll('group_', '')
        .replaceAll('party_', '')
        .replaceAll('req_', '')
        .trim();
  }

  static Future<Map<String, dynamic>?> payWithWallet({
    required double amount,
    String? planId,
    String? bookingId,
    String paymentType = 'booking_payment',
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final cleanBid = bookingId != null ? cleanBookingId(bookingId) : null;
      final cleanPid = planId != null ? cleanBookingId(planId) : null;
      final response = await post(
        '/api/mobile/wallet/pay-with-wallet',
        timeout: transactionalTimeout,
        body: {
          'userId': userId,
          'amount': amount,
          'planId': cleanPid,
          'bookingId': cleanBid,
          'paymentType': paymentType,
        },
      );
      if (response.body.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
        }
        return decoded;
      }
    } catch (e) {
      debugPrint('payWithWallet error: $e');
    }
    return null;
  }

  // â”€â”€â”€ Strangers Meet APIs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> submitStrangersMeetRequest({
    required String venueId,
    required String subject,
    required String tagline,
    required String eventDateTime,
    required int numberOfPersons,
    required double chargesPerHead,
    required String mobileNumber,
    String? alternateMobileNumber,
    // v2: Structured bank/UPI payment fields
    String? bankName,
    String? accountNumber,
    String? accountHolderName,
    String? ifscCode,
    String? upiId,
    String? upiNumber,
    String? foodPreference,
    String? drinkPreference,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await post(
        '/api/mobile/strangers-meet',
        body: {
          'userId': userId,
          'venueId': venueId,
          'subject': subject,
          'tagline': tagline,
          'eventDateTime': eventDateTime,
          'numberOfPersons': numberOfPersons,
          'chargesPerHead': chargesPerHead,
          'mobileNumber': mobileNumber,
          if (alternateMobileNumber != null && alternateMobileNumber.isNotEmpty)
            'alternateMobileNumber': alternateMobileNumber,
          if (bankName != null && bankName.isNotEmpty) 'bankName': bankName,
          if (accountNumber != null && accountNumber.isNotEmpty)
            'accountNumber': accountNumber,
          if (accountHolderName != null && accountHolderName.isNotEmpty)
            'accountHolderName': accountHolderName,
          if (ifscCode != null && ifscCode.isNotEmpty) 'ifscCode': ifscCode,
          if (upiId != null && upiId.isNotEmpty) 'upiId': upiId,
          if (upiNumber != null && upiNumber.isNotEmpty) 'upiNumber': upiNumber,
          if (foodPreference != null && foodPreference.isNotEmpty)
            'foodPreference': foodPreference,
          if (drinkPreference != null && drinkPreference.isNotEmpty)
            'drinkPreference': drinkPreference,
        },
      );
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
          RealtimeSyncManager.instance.triggerStrangerMeetSync();
          return true;
        }
        return false;
      } else {
        try {
          final data = jsonDecode(response.body);
          final msg =
              data['message'] ?? data['error'] ?? 'Failed to submit request';
          throw Exception(msg);
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('Failed to submit request');
        }
      }
    } catch (e) {
      debugPrint('submitStrangersMeetRequest error: $e');
      rethrow;
    }
  }

  static Future<List<StrangersMeetRequest>> fetchMyStrangersMeetRequests({
    String? status,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;

      final response = await get(
        '/api/mobile/strangers-meet/my-requests/$userId',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return (data['data'] as List)
              .map((json) => StrangersMeetRequest.fromJson(json))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('fetchMyStrangersMeetRequests error: $e');
    }
    return [];
  }

  static Future<List<StrangersMeetRequest>> fetchJoinedStrangersMeets() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
      final response = await get(
        '/api/mobile/strangers-meet/my-joined/$userId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return (data['data'] as List)
              .map((json) => StrangersMeetRequest.fromJson(json))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('fetchJoinedStrangersMeets error: $e');
    }
    return [];
  }

  static Future<StrangersMeetRequest?> fetchStrangersMeetRequestById(
    String id,
  ) async {
    try {
      final cleanId = id
          .trim()
          .replaceAll(
            RegExp(
              r'^(sm_host_approved_|sm_join_|sm_meet_|sm_|stranger_meet_|strangers_meet_|notification_|notif_)',
            ),
            '',
          )
          .trim();

      final response = await get('/api/mobile/strangers-meet/$cleanId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return StrangersMeetRequest.fromJson(data['data']);
        }
      }

      if (cleanId != id) {
        final response2 = await get('/api/mobile/strangers-meet/$id');
        if (response2.statusCode == 200) {
          final data2 = jsonDecode(response2.body);
          if (data2['success'] == true && data2['data'] != null) {
            return StrangersMeetRequest.fromJson(data2['data']);
          }
        }
      }
    } catch (e) {
      debugPrint('fetchStrangersMeetRequestById error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> initiateStrangersMeetPayment(
    String id,
  ) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/initiate-payment',
        body: {'userId': userId},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return data;
      } else {
        final msg =
            data['message'] ?? data['error'] ?? 'Failed to initiate payment';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('initiateStrangersMeetPayment error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> payStrangersMeetRequest(
    String id,
    String razorpayOrderId,
    String paymentId,
    String signature,
  ) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/pay',
        body: {
          'userId': userId,
          'razorpay_order_id': razorpayOrderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return data['data'];
      } else {
        final msg =
            data['message'] ?? data['error'] ?? 'Failed to confirm payment';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('payStrangersMeetRequest error: $e');
      rethrow;
    }
  }

  static Future<bool> updateStrangersMeetCharges(
    String id,
    double chargesPerHead,
  ) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await patch(
        '/api/mobile/strangers-meet/$id/charges',
        body: {'userId': userId, 'chargesPerHead': chargesPerHead},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
          RealtimeSyncManager.instance.triggerStrangerMeetSync();
          return true;
        }
      }
    } catch (e) {
      debugPrint('updateStrangersMeetCharges error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> initiateStrangersMeetJoinPayment(
    String id,
  ) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/join/initiate-payment',
        body: {'userId': userId},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return data;
      } else {
        final msg =
            data['message'] ??
            data['error'] ??
            'Failed to initiate join payment';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('initiateStrangersMeetJoinPayment error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> payStrangersMeetJoin(
    String id,
    String razorpayOrderId,
    String paymentId,
    String signature,
  ) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/join/confirm',
        body: {
          'userId': userId,
          'razorpay_order_id': razorpayOrderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return data['data'];
      } else {
        final msg =
            data['message'] ??
            data['error'] ??
            'Failed to confirm join payment';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('payStrangersMeetJoin error: $e');
      rethrow;
    }
  }

  static Future<bool> completeStrangersMeet(String id) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await patch(
        '/api/mobile/strangers-meet/$id/complete',
        body: {'userId': userId},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return true;
      } else {
        final msg =
            data['message'] ??
            data['error'] ??
            'Failed to complete strangers meet';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('completeStrangersMeet error: $e');
      rethrow;
    }
  }

  static Future<bool> sendStrangersMeetJoinRequest(
    String id, {
    String? foodPreference,
    String? drinkPreference,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/join-request',
        body: {
          'userId': userId,
          if (foodPreference != null && foodPreference.isNotEmpty)
            'foodPreference': foodPreference,
          if (drinkPreference != null && drinkPreference.isNotEmpty)
            'drinkPreference': drinkPreference,
        },
      );
      final data = jsonDecode(response.body);
      if ((response.statusCode == 201 || response.statusCode == 200) &&
          data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return true;
      } else {
        final msg =
            data['message'] ?? data['error'] ?? 'Failed to send join request';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('sendStrangersMeetJoinRequest error: $e');
      rethrow;
    }
  }

  static Future<bool> handleStrangersMeetJoinRequest(
    String id,
    String joinerId,
    String action,
  ) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await patch(
        '/api/mobile/strangers-meet/$id/join-request/$joinerId',
        body: {'userId': userId, 'action': action},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return true;
      } else {
        final msg =
            data['message'] ?? data['error'] ?? 'Failed to handle join request';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('handleStrangersMeetJoinRequest error: $e');
      rethrow;
    }
  }

  static Future<bool> submitStrangersMeetSettlement(
    String id,
    String bankDetails,
  ) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/settlement-request',
        body: {'userId': userId, 'bankDetails': bankDetails},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return true;
      } else {
        final msg =
            data['message'] ??
            data['error'] ??
            'Failed to submit settlement request';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('submitStrangersMeetSettlement error: $e');
      rethrow;
    }
  }

  /// Fetch financial breakdown for a Strangers Meet (platform fee, host profit, settlement)
  static Future<Map<String, dynamic>?> fetchStrangersMeetFinancials(
    String id,
  ) async {
    try {
      final response = await get('/api/mobile/strangers-meet/$id/financials');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data['data'];
      }
    } catch (e) {
      debugPrint('fetchStrangersMeetFinancials error: $e');
    }
    return null;
  }

  /// Host confirms Strangers Meet started + chooses meeting duration
  static Future<Map<String, dynamic>?> confirmStrangersMeetStarted(
    String id, {
    double? durationHours,
    String? customEndDateTime,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final Map<String, dynamic> body = {'userId': userId};
      if (durationHours != null) {
        body['durationHours'] = durationHours;
      }
      if (customEndDateTime != null) {
        body['customEndDateTime'] = customEndDateTime;
      }

      final response = await post(
        '/api/mobile/strangers-meet/$id/start',
        body: body,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return data['data'];
      } else {
        throw Exception(data['message'] ?? 'Failed to start meetup');
      }
    } catch (e) {
      debugPrint('confirmStrangersMeetStarted error: $e');
      rethrow;
    }
  }

  /// Host extends Strangers Meet duration
  static Future<Map<String, dynamic>?> extendStrangersMeetDuration(
    String id, {
    double? additionalHours,
    String? customEndDateTime,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final Map<String, dynamic> body = {'userId': userId};
      if (additionalHours != null) {
        body['additionalHours'] = additionalHours;
      }
      if (customEndDateTime != null) {
        body['customEndDateTime'] = customEndDateTime;
      }

      final response = await post(
        '/api/mobile/strangers-meet/$id/extend',
        body: body,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return data['data'];
      } else {
        throw Exception(data['message'] ?? 'Failed to extend meetup duration');
      }
    } catch (e) {
      debugPrint('extendStrangersMeetDuration error: $e');
      rethrow;
    }
  }

  /// Host marks Strangers Meet as not started
  static Future<Map<String, dynamic>?> reportStrangersMeetNotStarted(
    String id, {
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/not-started',
        body: {'userId': userId, 'reason': ?reason},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return data['data'];
      } else {
        throw Exception(
          data['message'] ?? 'Failed to mark meetup as not started',
        );
      }
    } catch (e) {
      debugPrint('reportStrangersMeetNotStarted error: $e');
      rethrow;
    }
  }

  /// Host confirms Strangers Meet ended
  static Future<Map<String, dynamic>?> confirmStrangersMeetEnded(
    String id,
  ) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not logged in');

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/confirm-ended',
        body: {'userId': userId},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return data['data'];
      } else {
        throw Exception(data['message'] ?? 'Failed to confirm meetup ended');
      }
    } catch (e) {
      debugPrint('confirmStrangersMeetEnded error: $e');
      rethrow;
    }
  }

  /// Joined member requests cancellation from a Stranger Meet
  static Future<Map<String, dynamic>> requestStrangersMeetCancellation(
    String id, {
    required String reason,
    String? otherReasonText,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not logged in'};
    }

    try {
      final Map<String, dynamic> body = {'userId': userId, 'reason': reason};
      if (otherReasonText != null && otherReasonText.trim().isNotEmpty) {
        body['otherReasonText'] = otherReasonText.trim();
      }

      final response = await post(
        '/api/mobile/strangers-meet/$id/joiner-cancel-request',
        body: body,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return {
          'success': true,
          'message': data['message'],
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message':
              data['message'] ??
              data['error'] ??
              'Failed to request cancellation',
        };
      }
    } catch (e) {
      debugPrint('requestStrangersMeetCancellation error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Host approves or rejects a joined member's cancellation request
  static Future<Map<String, dynamic>> respondStrangersMeetCancellation(
    String id,
    String cancellationId, {
    required String action,
    String? rejectReason,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not logged in'};
    }

    try {
      final Map<String, dynamic> body = {'userId': userId, 'action': action};
      if (rejectReason != null && rejectReason.trim().isNotEmpty) {
        body['rejectReason'] = rejectReason.trim();
      }

      final response = await patch(
        '/api/mobile/strangers-meet/$id/joiner-cancel-request/$cancellationId',
        body: body,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return {
          'success': true,
          'message': data['message'],
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message':
              data['message'] ??
              data['error'] ??
              'Failed to respond to cancellation',
        };
      }
    } catch (e) {
      debugPrint('respondStrangersMeetCancellation error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Host requests cancellation of Stranger Meet for Admin Review
  static Future<Map<String, dynamic>> requestStrangersMeetHostCancellation(
    String id, {
    required String reason,
    String? reasonText,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not logged in'};
    }

    try {
      final Map<String, dynamic> body = {'userId': userId, 'reason': reason};
      if (reasonText != null && reasonText.trim().isNotEmpty) {
        body['reasonText'] = reasonText.trim();
      }

      final response = await post(
        '/api/mobile/strangers-meet/$id/host-cancel-request',
        body: body,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerStrangerMeetSync();
        return {
          'success': true,
          'message': data['message'],
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message':
              data['message'] ??
              data['error'] ??
              'Failed to request host cancellation',
        };
      }
    } catch (e) {
      debugPrint('requestStrangersMeetHostCancellation error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Host requests cancellation of Large Party (>20) for Admin Review
  static Future<Map<String, dynamic>> requestLargePartyCancellation({
    required String bookingId,
    required String reason,
    String? reasonDetails,
    String? upiId,
    String? mobileNumber,
    String? accountHolderName,
    String? accountNumber,
    String? ifscCode,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not logged in'};
    }

    try {
      final Map<String, dynamic> body = {'userId': userId, 'reason': reason};
      if (reasonDetails != null && reasonDetails.trim().isNotEmpty) {
        body['reasonDetails'] = reasonDetails.trim();
      }
      if (upiId != null && upiId.trim().isNotEmpty) {
        body['upiId'] = upiId.trim();
      }
      if (mobileNumber != null && mobileNumber.trim().isNotEmpty) {
        body['mobileNumber'] = mobileNumber.trim();
      }
      if (accountHolderName != null && accountHolderName.trim().isNotEmpty) {
        body['accountHolderName'] = accountHolderName.trim();
      }
      if (accountNumber != null && accountNumber.trim().isNotEmpty) {
        body['accountNumber'] = accountNumber.trim();
      }
      if (ifscCode != null && ifscCode.trim().isNotEmpty) {
        body['ifscCode'] = ifscCode.trim();
      }

      final response = await post(
        '/api/mobile/bookings/$bookingId/cancel-request',
        body: body,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        return {
          'success': true,
          'message': data['message'],
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message':
              data['message'] ??
              data['error'] ??
              'Failed to submit cancellation request',
        };
      }
    } catch (e) {
      debugPrint('requestLargePartyCancellation error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Fetch cancellation status for a Large Party
  static Future<Map<String, dynamic>?> fetchLargePartyCancellationStatus(
    String bookingId,
  ) async {
    try {
      final response = await get(
        '/api/mobile/bookings/$bookingId/cancellation-status',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data;
        }
      }
      return null;
    } catch (e) {
      debugPrint('fetchLargePartyCancellationStatus error: $e');
      return null;
    }
  }

  /// Fetch cancellation status for a Stranger Meet
  static Future<Map<String, dynamic>?> fetchStrangersMeetCancellationStatus(
    String id,
  ) async {
    try {
      final response = await get(
        '/api/mobile/strangers-meet/$id/cancellation-status',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data['data'];
      }
    } catch (e) {
      debugPrint('fetchStrangersMeetCancellationStatus error: $e');
    }
    return null;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<List<HelpArticle>> fetchHelpCenterArticles() async {
    try {
      final response = await get('/api/support/help-center');
      //debugPrint('Help Center Response Status: ${response.statusCode}');
      //debugPrint('Help Center Response Body: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['articles'] != null) {
          return (data['articles'] as List)
              .map((json) => HelpArticle.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching help center: $e');
      return [];
    }
  }

  static Future<List<CommunityGuideline>> fetchCommunityGuidelines() async {
    try {
      final response = await get('/api/support/community-guidelines');
      //debugPrint('Community Guidelines Response Status: ${response.statusCode}');
      //debugPrint('Community Guidelines Response Body: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['guidelines'] != null) {
          return (data['guidelines'] as List)
              .map((json) => CommunityGuideline.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching community guidelines: $e');
      return [];
    }
  }

  static Future<List<LegalDocument>> fetchLegalDocuments() async {
    try {
      final response = await get('/api/support/legal');
      // debugPrint('Legal Documents Response Status: ${response.statusCode}');
      // debugPrint('Legal Documents Response Body: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['documents'] != null) {
          return (data['documents'] as List)
              .map((json) => LegalDocument.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching legal documents: $e');
      return [];
    }
  }

  static Future<LegalDocument?> fetchLegalDocumentByType(String type) async {
    try {
      final response = await get('/api/mobile/support/legal/type/$type');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['document'] != null) {
          return LegalDocument.fromJson(data['document']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching legal document of type $type: $e');
      return null;
    }
  }

  static void _checkAutoblockedResponse(http.Response response) {
    if (response.statusCode == 403) {
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['code'] == 'USER_AUTOBLOCKED') {
          final reason =
              data['autoblockedReason'] ??
              data['message'] ??
              'Suspended due to safety reports.';

          // Log out immediately
          clearAuthToken();

          // Navigate immediately to AutoblockedWarningScreen
          final nav = NotificationNavigator.navigator;
          if (nav != null) {
            nav.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => AutoblockedWarningScreen(reason: reason),
              ),
              (route) => false,
            );
          }
        }
      } catch (e) {
        debugPrint('Error parsing error response: $e');
      }
    }
  }

  /// Formats any low-level network/runtime exception into a user-friendly, non-technical message
  /// while ensuring technical errors are safely logged for debugging internally.
  static String formatUserFriendlyError(dynamic error) {
    if (error == null) return 'Something went wrong. Please try again.';
    final errStr = error.toString();
    debugPrint('[API_CLIENT_ERROR_DIAGNOSTIC] $errStr');

    if (error is TimeoutException ||
        errStr.contains('TimeoutException') ||
        errStr.contains('Future not completed') ||
        errStr.contains('timed out')) {
      return 'The connection took longer than expected. Please check your connection and tap to retry.';
    }
    if (errStr.contains('SocketException') ||
        errStr.contains('Connection refused') ||
        errStr.contains('Failed host lookup') ||
        errStr.contains('ClientException') ||
        errStr.contains('Network is unreachable')) {
      return 'Unable to reach Lunara servers. Please check your internet connection and try again.';
    }
    if (errStr.contains('500') || errStr.contains('Internal Server Error')) {
      return 'The server encountered a temporary issue. Please try again in a few moments.';
    }
    if (errStr.contains('502') ||
        errStr.contains('Bad Gateway') ||
        errStr.contains('503') ||
        errStr.contains('Service Unavailable')) {
      return 'Server is briefly undergoing maintenance. Please try again shortly.';
    }
    if (errStr.startsWith('Exception: ')) {
      return errStr.substring(11).trim();
    }
    if (errStr.startsWith('Error: ')) {
      return errStr.substring(7).trim();
    }
    return errStr;
  }

  static Future<http.Response> get(
    String endpoint, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$endpoint',
    ).replace(queryParameters: queryParameters);
    debugPrint('GET $uri');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (!kIsWeb) 'Accept-Encoding': 'gzip, deflate',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };

    if (body != null) {
      final request = http.Request('GET', uri);
      request.headers.addAll(headers);
      request.body = jsonEncode(body);
      final streamedResponse = await _httpClient
          .send(request)
          .timeout(timeout ?? defaultTimeout);
      final response = await http.Response.fromStream(streamedResponse);
      _checkAutoblockedResponse(response);
      return response;
    }

    // In-flight deduplication for identical concurrent GET calls
    final inFlightKey = uri.toString();
    if (_inFlightGets.containsKey(inFlightKey)) {
      return await _inFlightGets[inFlightKey]!;
    }

    final future = () async {
      int attempts = 0;
      while (true) {
        attempts++;
        try {
          final res = await _httpClient
              .get(uri, headers: headers)
              .timeout(timeout ?? defaultTimeout);
          _checkAutoblockedResponse(res);
          return res;
        } on TimeoutException {
          if (attempts >= 2) rethrow;
          debugPrint(
            '[ApiService] GET $uri timed out on attempt $attempts, retrying once...',
          );
          await Future.delayed(const Duration(milliseconds: 500));
        } on SocketException {
          // A lost SYN surfaces here once [_connectTimeout] fires. Waiting on
          // the operating system's retransmission backoff is pointless — a
          // fresh socket almost always connects immediately — so retry at once
          // rather than letting the caller see a hang or a failure. Retrying is
          // safe here because no request bytes ever reached the server, and it
          // stays confined to GET, which is idempotent by definition.
          if (attempts >= 2) rethrow;
          debugPrint(
            '[ApiService] GET $uri could not connect on attempt $attempts, retrying on a new socket...',
          );
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          rethrow;
        }
      }
    }();

    _inFlightGets[inFlightKey] = future;
    try {
      final response = await future;
      return response;
    } finally {
      _inFlightGets.remove(inFlightKey);
    }
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await put('/api/profile/update', body: data);
      debugPrint('updateProfile ${response.statusCode}: ${response.body}');
      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': resData['success'] == true,
          'message': resData['message'] ?? 'Profile updated successfully',
        };
      }
      return {
        'success': false,
        'message':
            resData['message'] ??
            resData['error'] ??
            'Failed to update profile (${response.statusCode})',
      };
    } catch (e) {
      debugPrint('updateProfile error: $e');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  static Future<bool> uploadProfilePhotos(
    List<Uint8List> fileBytes,
    List<String> fileNames, {
    bool isPrimary = false,
  }) async {
    try {
      debugPrint(
        'uploadProfilePhotos: preparing to send ${fileBytes.length} files, isPrimary: $isPrimary',
      );
      final files = <http.MultipartFile>[];
      for (int i = 0; i < fileBytes.length; i++) {
        String ext = fileNames[i].split('.').last.toLowerCase();
        String mimeType = 'jpeg';
        if (ext == 'png') mimeType = 'png';
        if (ext == 'gif') mimeType = 'gif';
        if (ext == 'webp') mimeType = 'webp';

        files.add(
          http.MultipartFile.fromBytes(
            'photos',
            fileBytes[i],
            filename: fileNames[i],
            contentType: MediaType('image', mimeType),
          ),
        );
      }
      final fields = <String, String>{'isPrimary': isPrimary.toString()};
      final response = await postMultipart(
        '/api/profile/photos',
        files: files,
        fields: fields,
      );
      debugPrint('uploadProfilePhotos status: ${response.statusCode}');
      debugPrint('uploadProfilePhotos body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        _lastProfileFetchTime = null;
        return true;
      }
    } catch (e) {
      debugPrint('uploadProfilePhotos error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>> deleteProfilePhoto(String photoId) async {
    try {
      final response = await delete('/api/profile/photos/$photoId');
      final Map<String, dynamic> data = jsonDecode(response.body);
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        _lastProfileFetchTime = null;
        return {
          'success': true,
          'message': data['message'] ?? 'Photo deleted successfully!',
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to delete photo.',
      };
    } catch (e) {
      debugPrint('deleteProfilePhoto error: $e');
      return {'success': false, 'message': 'Failed to delete photo: $e'};
    }
  }

  static Future<Map<String, dynamic>> setPrimaryPhoto(String photoId) async {
    try {
      final userId = currentUserId;
      final requestBody = userId != null
          ? {'userId': userId}
          : <String, dynamic>{};

      var response = await put(
        '/api/profile/photos/$photoId/primary',
        body: requestBody,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        response = await put(
          '/api/mobile/user/photos/$photoId/primary',
          body: requestBody,
        );
      }

      Map<String, dynamic> data = {};
      try {
        if (response.body.isNotEmpty) {
          data = jsonDecode(response.body);
        }
      } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        _lastProfileFetchTime = null;
        return {
          'success': true,
          'message': data['message'] ?? 'Profile picture updated successfully!',
          'data': data['data'],
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update profile picture.',
      };
    } catch (e) {
      debugPrint('setPrimaryPhoto error: $e');
      return {
        'success': false,
        'message': 'Failed to update profile picture: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    try {
      final response = await post(
        '/api/profile/change-password',
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          'confirmPassword': confirmPassword,
        },
      );
      final body = json.decode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': body['message'] ?? 'Password updated successfully!',
        };
      } else {
        String msg = body['message'] ?? 'Failed to update password';
        if (body['errors'] is List && (body['errors'] as List).isNotEmpty) {
          final firstErr = body['errors'][0];
          if (firstErr is Map && firstErr['msg'] != null) {
            msg = firstErr['msg'];
          } else if (firstErr is String) {
            msg = firstErr;
          }
        }
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      debugPrint('changePassword error: $e');
      return {
        'success': false,
        'message': 'Failed to update password. Please try again.',
      };
    }
  }

  static Future<http.Response> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('PUT $uri');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (!kIsWeb) 'Accept-Encoding': 'gzip, deflate',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final response = await _httpClient
        .put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout ?? defaultTimeout);
    _checkAutoblockedResponse(response);
    return response;
  }

  static Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('POST $uri');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (!kIsWeb) 'Accept-Encoding': 'gzip, deflate',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final response = await _httpClient
        .post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout ?? defaultTimeout);
    _checkAutoblockedResponse(response);
    return response;
  }

  static Future<http.Response> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('PATCH $uri');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (!kIsWeb) 'Accept-Encoding': 'gzip, deflate',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final response = await _httpClient
        .patch(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout ?? defaultTimeout);
    _checkAutoblockedResponse(response);
    return response;
  }

  static Future<http.Response> delete(
    String endpoint, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('DELETE $uri');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (!kIsWeb) 'Accept-Encoding': 'gzip, deflate',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final request = http.Request('DELETE', uri);
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _httpClient
        .send(request)
        .timeout(timeout ?? defaultTimeout);
    final response = await http.Response.fromStream(streamed);
    _checkAutoblockedResponse(response);
    return response;
  }

  // â”€â”€â”€ Chat Module â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Step 2 â€” GET /api/mobile/chat/conversations?userId=
  static Future<List<Map<String, dynamic>>> fetchConversations(
    String userId, {
    bool forceRefresh = false,
  }) async {
    // The chat list had no cache at all, so every visit — and the dashboard's
    // background prewarm, and the 45s poll — paid a full round trip before
    // anything could render. A short window is enough to make re-entering the
    // tab instant without ever showing a stale conversation for long; sockets
    // (`new_message`, `messages_read`) still update the list in real time.
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedConversations != null &&
        _conversationsCacheTime != null &&
        now.difference(_conversationsCacheTime!).inSeconds < 30) {
      return _cachedConversations!;
    }

    try {
      final response = await get(
        '/api/mobile/chat/conversations',
        queryParameters: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final list = List<Map<String, dynamic>>.from(data['data']);
          _cachedConversations = list;
          _conversationsCacheTime = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('fetchConversations error: $e');
      // A transient failure should not wipe the list the user is looking at.
      if (_cachedConversations != null) return _cachedConversations!;
    }
    return _cachedConversations ?? [];
  }

  /// Step 1 â€” GET /api/mobile/chat/icebreakers
  static Future<List<Map<String, dynamic>>> fetchIcebreakers() async {
    try {
      final response = await get('/api/mobile/chat/icebreakers');
      //debugPrint('fetchIcebreakers ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchIcebreakers error: $e');
    }
    return [];
  }

  /// Step 3 â€” POST /api/mobile/chat/conversations
  /// Returns conversationId (existing or new).
  static Future<String?> createOrGetConversation({
    required String userId,
    required String otherUserId,
    String? contextType,
    String? contextId,
  }) async {
    try {
      final body = <String, dynamic>{
        'userId': userId,
        'otherUserId': otherUserId,
      };
      if (contextType != null && contextType.isNotEmpty) {
        body['contextType'] = contextType;
      }
      if (contextId != null && contextId.isNotEmpty) {
        body['contextId'] = contextId;
        body['contextType'] ??= 'plan';
      }
      final response = await post('/api/mobile/chat/conversations', body: body);
      debugPrint(
        '[Chat] createOrGetConversation status=${response.statusCode}',
      );
      debugPrint(
        '[Chat] createOrGetConversation body=${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}',
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final convId =
              data['data']?['conversationId']?.toString() ??
              data['data']?['id']?.toString();
          debugPrint('[Chat] got conversationId: $convId');
          return convId;
        }
      } else {
        debugPrint('[Chat] createOrGetConversation FAILED: ${response.body}');
      }
    } catch (e) {
      debugPrint('createOrGetConversation error: $e');
    }
    return null;
  }

  /// Step 4 â€” GET /api/mobile/chat/conversations/:id/messages
  static Future<List<Map<String, dynamic>>> fetchMessages(
    String conversationId,
    String userId, {
    String? before,
    int limit = 30,
  }) async {
    try {
      final params = <String, String>{
        'userId': userId,
        'limit': limit.toString(),
      };
      if (before != null && before.isNotEmpty) {
        params['before'] = before;
      }
      final response = await get(
        '/api/mobile/chat/conversations/$conversationId/messages',
        queryParameters: params,
      );
      debugPrint(
        '[Chat] fetchMessages status=${response.statusCode} convId=$conversationId',
      );
      debugPrint(
        '[Chat] fetchMessages body=${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final msgs = List<Map<String, dynamic>>.from(data['data']);
          debugPrint('[Chat] fetchMessages returned ${msgs.length} messages');
          return msgs;
        }
      } else {
        debugPrint('[Chat] fetchMessages FAILED: ${response.body}');
      }
    } catch (e) {
      debugPrint('fetchMessages error: $e');
    }
    return [];
  }

  /// Step 5A-5E — POST /api/mobile/chat/conversations/:id/messages
  static Future<Map<String, dynamic>?> sendMessage(
    String conversationId, {
    required String senderId,
    required String type, // text | image | sticker | icebreaker | invitation
    String? content,
    String? mediaUrl,
    String? mediaMimeType,
    String? invitationRef,
    String? invitationRefType,
    String? invitationTime,
    String? clientMessageId,
    String? replyToMessageId,
  }) async {
    try {
      final body = <String, dynamic>{'senderId': senderId, 'type': type};
      if (content != null) body['content'] = content;
      if (mediaUrl != null) body['mediaUrl'] = mediaUrl;
      if (mediaMimeType != null) body['mediaMimeType'] = mediaMimeType;
      if (invitationRef != null) body['invitationRef'] = invitationRef;
      if (invitationRefType != null) {
        body['invitationRefType'] = invitationRefType;
      }
      if (invitationTime != null) body['invitationTime'] = invitationTime;
      if (clientMessageId != null) body['clientMessageId'] = clientMessageId;
      if (replyToMessageId != null) body['replyToMessageId'] = replyToMessageId;

      final response = await post(
        '/api/mobile/chat/conversations/$conversationId/messages',
        body: body,
      );
      debugPrint(
        '[Chat] sendMessage status=${response.statusCode} convId=$conversationId',
      );
      debugPrint(
        '[Chat] sendMessage body=${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}',
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data']);
        }
      } else {
        debugPrint('[Chat] sendMessage FAILED: ${response.body}');
      }
    } catch (e) {
      debugPrint('sendMessage error: $e');
    }
    return null;
  }

  /// Step 6A/6B â€” PATCH .../messages/:messageId/invitation
  static Future<bool> respondToInvitation(
    String conversationId,
    String messageId, {
    required String userId,
    required String action, // accept | decline
  }) async {
    try {
      final response = await patch(
        '/api/mobile/chat/conversations/$conversationId/messages/$messageId/invitation',
        body: {'userId': userId, 'action': action},
      );
      //debugPrint('respondToInvitation ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('respondToInvitation error: $e');
    }
    return false;
  }

  /// Step 7 â€” PATCH .../conversations/:id/read
  static Future<void> markConversationRead(
    String conversationId,
    String userId,
  ) async {
    try {
      // ignore: unused_local_variable
      final response = await patch(
        '/api/mobile/chat/conversations/$conversationId/read',
        body: {'userId': userId},
      );
      //debugPrint('markConversationRead ${response.statusCode}');
    } catch (e) {
      debugPrint('markConversationRead error: $e');
    }
  }

  /// DELETE /api/mobile/chat/conversations/:id/messages/:msgId
  static Future<bool> deleteMessage({
    required String conversationId,
    required String messageId,
    required String userId,
    bool deleteForEveryone = true,
  }) async {
    try {
      final response = await delete(
        '/api/mobile/chat/conversations/$conversationId/messages/$messageId',
        body: {'userId': userId, 'deleteForEveryone': deleteForEveryone},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('deleteMessage error: $e');
    }
    return false;
  }

  /// POST /api/mobile/chat/conversations/:id/messages/batch-delete
  static Future<bool> deleteMessagesBatch({
    required String conversationId,
    required List<String> messageIds,
    required String userId,
    bool deleteForEveryone = true,
  }) async {
    try {
      final response = await post(
        '/api/mobile/chat/conversations/$conversationId/messages/batch-delete',
        body: {
          'userId': userId,
          'messageIds': messageIds,
          'deleteForEveryone': deleteForEveryone,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('deleteMessagesBatch error: $e');
    }
    return false;
  }

  /// DELETE /api/mobile/chat/conversations/:id/messages (or POST .../clear)
  static Future<bool> clearChat(
    String conversationId,
    String userId, {
    bool clearForEveryone = false,
  }) async {
    try {
      final response = await delete(
        '/api/mobile/chat/conversations/$conversationId/messages',
        body: {'userId': userId, 'clearForEveryone': clearForEveryone},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('clearChat error: $e');
    }
    return false;
  }

  /// DELETE /api/mobile/chat/conversations/:id
  static Future<bool> deleteConversation(
    String conversationId,
    String userId, {
    bool deleteForEveryone = false,
  }) async {
    try {
      final response = await delete(
        '/api/mobile/chat/conversations/$conversationId',
        body: {'userId': userId, 'deleteForEveryone': deleteForEveryone},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('deleteConversation error: $e');
    }
    return false;
  }

  /// GET /api/mobile/user/:otherUserId/status
  /// Returns the online status and last active timestamp for a specific user.
  static Future<Map<String, dynamic>?> getUserOnlineStatus(
    String otherUserId,
  ) async {
    try {
      final response = await get('/api/mobile/user/$otherUserId/status');
      //debugPrint('getUserOnlineStatus ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
        // Some implementations return the payload directly
        if (data['isOnline'] != null) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('getUserOnlineStatus error: $e');
    }
    return null;
  }

  // ─── Push Notification Token ──────────────────────────────────────────

  /// Sends the FCM device token to the backend for push notification delivery.
  static Future<bool> registerFcmToken(String token) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final response = await post(
        '/api/mobile/user/fcm-token',
        body: {'userId': userId, 'token': token, 'platform': platform},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('FCM token registered successfully');
        return true;
      }
      debugPrint('FCM token registration failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('registerFcmToken error: $e');
    }
    return false;
  }

  static Future<bool> unregisterFcmToken(String token) async {
    final userId = currentUserId;
    try {
      final response = await post(
        '/api/mobile/user/unregister-fcm-token',
        body: {'userId': userId, 'token': token},
      );
      if (response.statusCode == 200) {
        debugPrint('FCM token unregistered successfully');
        return true;
      }
    } catch (e) {
      debugPrint('unregisterFcmToken error: $e');
    }
    return false;
  }

  static Future<bool> blockUser(String targetUserId) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;
      final response = await post(
        '/api/mobile/user/block',
        body: {'userId': userId, 'targetUserId': targetUserId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('blockUser error: $e');
    }
    return false;
  }

  static Future<bool> unblockUser(String targetUserId) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;
      final response = await post(
        '/api/mobile/user/unblock',
        body: {'userId': userId, 'targetUserId': targetUserId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('unblockUser error: $e');
    }
    return false;
  }

  static Future<bool> reportUser(String targetUserId, String reason) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;
      final response = await post(
        '/api/mobile/user/report',
        body: {
          'userId': userId,
          'targetUserId': targetUserId,
          'reason': reason,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('reportUser error: $e');
    }
    return false;
  }

  static Future<List<String>> getBlockedUsers() async {
    try {
      final userId = currentUserId;
      if (userId == null) return [];
      final response = await get('/api/mobile/user/blocks?userId=$userId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<String>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('getBlockedUsers error: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getBlockedUsersDetails() async {
    try {
      final userId = currentUserId;
      if (userId == null) return [];
      final response = await get(
        '/api/mobile/user/blocks/details?userId=$userId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('getBlockedUsersDetails error: $e');
    }
    return [];
  }

  static Future<bool> updateUserPreferences({
    required bool showMeInMatching,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) return false;

      final uri = Uri.parse('$baseUrl/api/mobile/user/profile-setup');
      final headers = {'Content-Type': 'application/json'};
      if (_authToken != null) {
        headers['Authorization'] = 'Bearer $_authToken';
      }

      final response = await http.put(
        uri,
        headers: headers,
        body: jsonEncode({
          'userId': userId,
          'showMeInMatching': showMeInMatching,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('updateUserPreferences error: $e');
    }
    return false;
  }

  static bool get isLoggedIn =>
      _authToken != null && _authToken!.trim().isNotEmpty;

  static String? get currentUserId {
    if (_authToken != null && _authToken!.trim().isNotEmpty) {
      try {
        final parts = _authToken!.split('.');
        if (parts.length == 3) {
          String normalized = parts[1]
              .replaceAll('-', '+')
              .replaceAll('_', '/');
          switch (normalized.length % 4) {
            case 2:
              normalized += '==';
              break;
            case 3:
              normalized += '=';
              break;
          }
          final payload = utf8.decode(base64.decode(normalized));
          final data = jsonDecode(payload);
          final rawId =
              data['userId']?.toString() ??
              data['id']?.toString() ??
              data['_id']?.toString() ??
              data['user_id']?.toString() ??
              data['sub']?.toString();
          if (rawId != null &&
              rawId != 'undefined' &&
              rawId != 'null' &&
              rawId.trim().isNotEmpty) {
            return rawId;
          }
        }
      } catch (e) {
        debugPrint('Error decoding JWT in currentUserId: $e');
      }
    }
    if (cachedCurrentUser?.id != null &&
        cachedCurrentUser!.id.trim().isNotEmpty) {
      return cachedCurrentUser!.id;
    }
    return null;
  }

  // â”€â”€â”€ Notifications & Local Persistent Read State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static final Set<String> localReadRequestIds = {};
  static final Set<String> localReadNotificationIds = {};
  static bool _readIdsLoaded = false;
  static bool get localReadIdsLoaded => _readIdsLoaded;

  static Future<void> loadLocalReadIds() async {
    _ensureLocalStateForCurrentUser();
    if (_readIdsLoaded) return;
    try {
      final userId = currentUserId;
      if (userId == null || userId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final reqs =
          prefs.getStringList(
            _userPreferenceKey('localReadRequestIds', userId),
          ) ??
          [];
      final notifs =
          prefs.getStringList(
            _userPreferenceKey('localReadNotificationIds', userId),
          ) ??
          [];
      localReadRequestIds.clear();
      localReadRequestIds.addAll(reqs);
      localReadNotificationIds.clear();
      localReadNotificationIds.addAll(notifs);
      _readIdsLoaded = true;
    } catch (e) {
      debugPrint('Error loading local read IDs: $e');
    }
  }

  static Future<void> saveLocalReadRequestIds() async {
    try {
      _ensureLocalStateForCurrentUser();
      final userId = currentUserId;
      if (userId == null || userId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _userPreferenceKey('localReadRequestIds', userId),
        localReadRequestIds.toList(),
      );
    } catch (e) {
      debugPrint('Error saving local read request IDs: $e');
    }
  }

  static Future<void> saveLocalReadNotificationIds() async {
    try {
      _ensureLocalStateForCurrentUser();
      final userId = currentUserId;
      if (userId == null || userId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _userPreferenceKey('localReadNotificationIds', userId),
        localReadNotificationIds.toList(),
      );
    } catch (e) {
      debugPrint('Error saving local read notification IDs: $e');
    }
  }

  static Future<void> saveLocalReadIds() async {
    await Future.wait([
      saveLocalReadRequestIds(),
      saveLocalReadNotificationIds(),
    ]);
  }

  /// Fetch in-app notifications for current user
  static Future<List<Map<String, dynamic>>> fetchNotifications({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedNotifications != null &&
        _notificationsCacheTime != null) {
      if (now.difference(_notificationsCacheTime!).inSeconds < 20) {
        return _cachedNotifications!;
      }
    }

    await loadLocalReadIds();
    try {
      // Limit to max 20 IDs in query parameter to avoid HTTP 414 / 400 URL length limits
      final recentReadNotifIds = localReadNotificationIds.toList();
      final slicedNotifIds = recentReadNotifIds.length > 20
          ? recentReadNotifIds.sublist(recentReadNotifIds.length - 20)
          : recentReadNotifIds;

      final response = await get(
        '/api/mobile/user/notifications',
        queryParameters: {
          'userId': userId,
          'readNotificationIds': slicedNotifIds.join(','),
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] ?? data['notifications'];
        if (list is List) {
          final result = List<Map<String, dynamic>>.from(list);
          _cachedNotifications = result;
          _notificationsCacheTime = DateTime.now();
          return result;
        }
      }
    } catch (e) {
      debugPrint('fetchNotifications error: $e');
    }
    if (_cachedNotifications != null) {
      return _cachedNotifications!;
    }
    return [];
  }

  static Future<Map<String, int>>? _inFlightBadgeCounts;
  static DateTime? _badgeCountsCacheTime;
  static Map<String, int>? _cachedBadgeCounts;

  static final ValueNotifier<int> chatBadgeNotifier = ValueNotifier<int>(0);

  /// Optimistically update the chat badge count in memory and notify listeners
  static void updateChatBadgeCount(int count) {
    final cleanCount = count < 0 ? 0 : count;
    if (_cachedBadgeCounts != null) {
      _cachedBadgeCounts!['chatCount'] = cleanCount;
      _cachedBadgeCounts!['totalCount'] =
          (_cachedBadgeCounts!['liveFeedCount'] ?? 0) + cleanCount;
    }
    chatBadgeNotifier.value = cleanCount;
  }

  /// Fetches real unread count for badge indicators
  static Future<Map<String, int>> fetchBadgeCounts({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'liveFeedCount': 0, 'chatCount': 0, 'totalCount': 0};
    }

    final now = DateTime.now();
    if (forceRefresh) {
      _badgeCountsCacheTime = null;
    } else if (_cachedBadgeCounts != null &&
        _badgeCountsCacheTime != null &&
        now.difference(_badgeCountsCacheTime!).inSeconds < 15) {
      return _cachedBadgeCounts!;
    }

    if (_inFlightBadgeCounts != null) {
      return _inFlightBadgeCounts!;
    }

    _inFlightBadgeCounts = () async {
      await loadLocalReadIds();
      try {
        // Limit to max 20 IDs in query parameters to avoid HTTP 414 / 400 URL length limits
        final recentReqIds = localReadRequestIds.toList();
        const maxSlice = 20;
        final slicedReqIds = recentReqIds.length > maxSlice
            ? recentReqIds.sublist(recentReqIds.length - maxSlice)
            : recentReqIds;

        final recentNotifIds = localReadNotificationIds.toList();
        final slicedNotifIds = recentNotifIds.length > maxSlice
            ? recentNotifIds.sublist(recentNotifIds.length - maxSlice)
            : recentNotifIds;

        final response = await get(
          '/api/mobile/user/badge-counts',
          queryParameters: {
            'userId': userId,
            'readRequestIds': slicedReqIds.join(','),
            'readNotificationIds': slicedNotifIds.join(','),
          },
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['data'] != null) {
            final chatCount = data['data']['chatCount'] ?? 0;
            _cachedBadgeCounts = {
              'liveFeedCount': data['data']['liveFeedCount'] ?? 0,
              'chatCount': chatCount,
              'totalCount': data['data']['totalCount'] ?? 0,
            };
            _badgeCountsCacheTime = DateTime.now();
            chatBadgeNotifier.value = chatCount;
            return _cachedBadgeCounts!;
          }
        }
      } catch (e) {
        debugPrint('fetchBadgeCounts error: $e');
      } finally {
        _inFlightBadgeCounts = null;
      }
      return _cachedBadgeCounts ??
          {'liveFeedCount': 0, 'chatCount': 0, 'totalCount': 0};
    }();

    return _inFlightBadgeCounts!;
  }

  /// Mark a notification as read
  static Future<void> markNotificationRead(String notificationId) async {
    final userId = currentUserId;
    await loadLocalReadIds();
    localReadNotificationIds.add(notificationId);
    await saveLocalReadNotificationIds();
    try {
      // Pass userId so the server can scope read state per user
      await patch(
        '/api/mobile/user/notifications/$notificationId/read',
        body: userId != null ? {'userId': userId} : null,
      );
    } catch (e) {
      debugPrint('markNotificationRead error: $e');
    }
  }

  /// Mark all notifications as read on backend (sets live feed unread count to 0)
  static Future<bool> markAllNotificationsAsRead() async {
    final userId = currentUserId;
    if (userId == null) return false;
    _cachedBadgeCounts = {
      'liveFeedCount': 0,
      'chatCount': _cachedBadgeCounts?['chatCount'] ?? 0,
      'totalCount': _cachedBadgeCounts?['chatCount'] ?? 0,
    };
    _badgeCountsCacheTime = DateTime.now();
    try {
      final response = await post(
        '/api/mobile/user/notifications/mark-all-read',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('markAllNotificationsAsRead error: $e');
    }
    return false;
  }

  /// Clear all notifications (mark as cleared persistently)
  static Future<bool> clearAllNotifications() async {
    final userId = currentUserId;
    if (userId == null) return false;
    _cachedBadgeCounts = {
      'liveFeedCount': 0,
      'chatCount': _cachedBadgeCounts?['chatCount'] ?? 0,
      'totalCount': _cachedBadgeCounts?['chatCount'] ?? 0,
    };
    _badgeCountsCacheTime = DateTime.now();
    try {
      final response = await post(
        '/api/mobile/user/notifications/clear-all',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('clearAllNotifications error: $e');
    }
    return false;
  }

  /// Mark an incoming join request as read
  static Future<void> markRequestRead(String reqId) async {
    final userId = currentUserId;
    await loadLocalReadIds();
    localReadRequestIds.add(reqId);
    await saveLocalReadRequestIds();
    try {
      // Pass userId so the server can scope read state per user
      await patch(
        '/api/mobile/user/requests/$reqId/read',
        body: userId != null ? {'userId': userId} : null,
      );
    } catch (e) {
      debugPrint('markRequestRead error: $e');
    }
  }

  /// Reject/decline a party plan request
  static Future<bool> rejectPartyPlanRequest(
    String rawReqId, {
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final reqId = cleanBookingId(rawReqId);
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/reject',
        body: {'userId': userId, 'reason': ?reason},
        timeout: transactionalTimeout,
      );
      if (response.statusCode == 200) {
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerPartyPlanSync();
        return true;
      }
    } catch (e) {
      debugPrint('rejectPartyPlanRequest error: $e');
    }
    return false;
  }

  /// Accept a party plan invite
  static Future<Map<String, dynamic>?> acceptPartyPlanInvite(
    String rawReqId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final reqId = cleanBookingId(rawReqId);
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/accept-invite',
        body: {'userId': userId},
        timeout: transactionalTimeout,
      );
      if (response.body.isNotEmpty) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) {
            notifyFeedNeedsRefresh();
            RealtimeSyncManager.instance.triggerPartyPlanSync();
            return data;
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('acceptPartyPlanInvite error: $e');
      return {'success': false, 'message': formatUserFriendlyError(e)};
    }
    return null;
  }

  /// Joiner proceeds to pay after host accepts
  static Future<Map<String, dynamic>?> initiateJoinerPayment(
    String rawReqId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final reqId = cleanBookingId(rawReqId);
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/initiate-joiner-payment',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data;
      }
    } catch (e) {
      debugPrint('initiateJoinerPayment error: $e');
    }
    return null;
  }

  /// Host proceeds to pay deposit after accepting
  static Future<Map<String, dynamic>?> initiateHostPayment(
    String planId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/initiate-host-payment',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data;
      }
    } catch (e) {
      debugPrint('initiateHostPayment error: $e');
    }
    return null;
  }

  static Future<http.Response> postMultipart(
    String endpoint, {
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('POST MULTIPART $uri');

    final request = http.MultipartRequest('POST', uri);

    if (_authToken != null) {
      request.headers['Authorization'] = 'Bearer $_authToken';
    }

    if (fields != null) {
      request.fields.addAll(fields);
    }

    if (files != null) {
      request.files.addAll(files);
    }

    final streamedResponse = await _httpClient.send(request);
    return await http.Response.fromStream(streamedResponse);
  }

  // â”€â”€ Chat Subscription APIs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<Map<String, dynamic>?> getChatSessionStatus(
    String conversationId,
  ) async {
    try {
      final response = await get(
        '/api/mobile/user/chat/session-status/$conversationId',
        queryParameters: {'userId': currentUserId ?? ''},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
      }
    } catch (e) {
      debugPrint('getChatSessionStatus error: \$e');
    }
    return null;
  }

  static Future<bool> extendChat(
    String conversationId, {
    String? paymentId,
  }) async {
    try {
      final response = await post(
        '/api/mobile/user/chat/extend',
        body: {
          'conversationId': conversationId,
          'userId': currentUserId,
          'paymentId': ?paymentId,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('extendChat error: \$e');
    }
    return false;
  }

  static Future<bool> requestChatExtension(
    String conversationId,
    String targetUserId,
  ) async {
    try {
      final response = await post(
        '/api/mobile/user/chat/request-extension',
        body: {
          'conversationId': conversationId,
          'requesterId': currentUserId,
          'targetUserId': targetUserId,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('requestChatExtension error: \$e');
    }
    return false;
  }

  static Future<bool> acceptChatExtensionRequest(
    String conversationId, {
    String? requestedById,
    String? paymentId,
  }) async {
    try {
      final response = await post(
        '/api/mobile/user/chat/accept-extension-request',
        body: {
          'conversationId': conversationId,
          'userId': currentUserId,
          'requestedById': ?requestedById,
          'paymentId': ?paymentId,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('acceptChatExtensionRequest error: \$e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> getAdminChatSettings() async {
    try {
      final response = await get('/api/admin/settings/chat');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? {});
        }
      }
    } catch (e) {
      debugPrint('getAdminChatSettings error: \$e');
    }
    return null;
  }

  static Future<bool> updateAdminChatSettings({
    required int freeDays,
    required int extensionDays,
    required double extensionPrice,
  }) async {
    try {
      final response = await put(
        '/api/admin/settings/chat',
        body: {
          'freeDays': freeDays,
          'extensionDays': extensionDays,
          'extensionPrice': extensionPrice,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('updateAdminChatSettings error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> initiateLargePartyPayment(
    String bookingId,
  ) async {
    try {
      final cleanId = cleanBookingId(bookingId);
      final userId = currentUserId; // fallback for auth extraction on backend
      final response = await post(
        '/api/mobile/bookings/$cleanId/initiate-large-party-payment',
        timeout: transactionalTimeout,
        body: {
          'paymentMethod': 'razorpay',
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      } else {
        debugPrint(
          'initiateLargePartyPayment error [${response.statusCode}]: ${response.body}',
        );
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            return Map<String, dynamic>.from(data);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('initiateLargePartyPayment error: $e');
    }
    return null;
  }

  static Future<bool> verifyLargePartyPayment(
    String bookingId, {
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final cleanId = cleanBookingId(bookingId);
      final response = await post(
        '/api/mobile/bookings/$cleanId/verify-large-party-payment',
        timeout: transactionalTimeout,
        body: {
          'razorpay_order_id': razorpayOrderId,
          'razorpay_payment_id': razorpayPaymentId,
          'razorpay_signature': razorpaySignature,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('verifyLargePartyPayment error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> createBooking({
    required String venueId,
    required String bookingDate,
    required String startTime,
    required String tablePackage,
    String goingMode = 'solo',
    int numberOfGuests = 1,
    String? partySubject,
    String? partyRequirement,
    String? partyDescription,
    String? mobileNumber,
    String? optionalMobileNumber,
    bool isUpcomingNight = false,
    String? paymentMode,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/bookings',
        body: {
          'userId': userId,
          'venueId': venueId,
          'bookingDate': bookingDate,
          'startTime': startTime,
          'tablePackage': tablePackage,
          'goingMode': goingMode,
          'numberOfGuests': numberOfGuests,
          'partySubject': partySubject,
          'partyRequirement': partyRequirement,
          'partyDescription': partyDescription,
          'mobileNumber': mobileNumber,
          'optionalMobileNumber': optionalMobileNumber,
          'isUpcomingNight': isUpcomingNight,
          if (paymentMode != null && paymentMode.isNotEmpty)
            'paymentMode': paymentMode,
        },
      );
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('createBooking error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> createPartyBooking({
    required String partyEventId,
    required int quantity,
    String? eventDate,
    String? time,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final cleanId = cleanBookingId(partyEventId);
    try {
      final response = await post(
        '/api/mobile/bookings/party-event',
        body: {
          'userId': userId,
          'partyEventId': cleanId,
          'quantity': quantity,
          if (eventDate != null && eventDate.isNotEmpty) 'eventDate': eventDate,
          if (time != null && time.isNotEmpty) 'time': time,
        },
      );
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('createPartyBooking error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> payNowBooking(
    String bookingId, {
    String? paymentMethod,
    String? transactionId,
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? razorpaySignature,
  }) async {
    final userId = currentUserId;
    try {
      final response = await post(
        '/api/mobile/bookings/$bookingId/pay-now',
        timeout: transactionalTimeout,
        body: {
          'userId': userId,
          ...?paymentMethod == null ? null : {'paymentMethod': paymentMethod},
          ...?transactionId == null ? null : {'transactionId': transactionId},
          ...?razorpayOrderId == null
              ? null
              : {'razorpay_order_id': razorpayOrderId},
          ...?razorpayPaymentId == null
              ? null
              : {'razorpay_payment_id': razorpayPaymentId},
          ...?razorpaySignature == null
              ? null
              : {'razorpay_signature': razorpaySignature},
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final res = Map<String, dynamic>.from(
            data['data'] is Map ? data['data'] : data,
          );
          res['success'] = true;
          return res;
        }
      }
      if (response.statusCode == 402) {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'insufficientBalance': true,
          'message': data['message'] ?? 'Insufficient wallet balance',
          'data': data['data'],
        };
      }
    } catch (e) {
      debugPrint('payNowBooking error: $e');
    }
    return null;
  }

  // â”€â”€ Upcoming Night Partner Discovery & Matching â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<bool> checkNightInterest({
    required String venueId,
    required String date,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await get(
        '/api/mobile/nights/check-interest',
        queryParameters: {
          'userId': userId,
          'venueId': venueId,
          'eventDate': date,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isInterested'] == true;
      }
    } catch (e) {
      debugPrint('checkNightInterest error: $e');
    }
    return false;
  }

  static Future<bool> markNightInterested({
    required String venueId,
    required String date,
    String? time,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/nights/interested',
        body: {
          'userId': userId,
          'venueId': venueId,
          'eventDate': date,
          'eventTime': time ?? '20:00',
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          notifyFeedNeedsRefresh();
          RealtimeSyncManager.instance.triggerLiveFeedSync();
          return true;
        }
      }
    } catch (e) {
      debugPrint('markNightInterested error: $e');
    }
    return false;
  }

  static Future<bool> removeNightInterest({
    required String venueId,
    required String date,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await delete(
        '/api/mobile/nights/interested',
        body: {'userId': userId, 'venueId': venueId, 'eventDate': date},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          notifyFeedNeedsRefresh();
          RealtimeSyncManager.instance.triggerLiveFeedSync();
          return true;
        }
      }
    } catch (e) {
      debugPrint('removeNightInterest error: $e');
    }
    return false;
  }

  static Future<List<Map<String, dynamic>>> fetchInterestedPartners({
    required String venueId,
    required String date,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final response = await get(
        '/api/mobile/nights/interested-partners',
        queryParameters: {
          'hostId': userId,
          'venueId': venueId,
          'eventDate': date,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchInterestedPartners error: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchAvailableInvitees({
    required String venueId,
    required String date,
    String? search,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final queryParams = <String, String>{
        'hostId': userId,
        'venueId': venueId,
        'eventDate': date,
      };
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }
      final response = await get(
        '/api/mobile/nights/available-invitees',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchAvailableInvitees error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> fetchPartnerProfilePreview(
    String targetUserId,
  ) async {
    try {
      final response = await get(
        '/api/mobile/nights/partners/$targetUserId/profile',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchPartnerProfilePreview error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> sendNightPartnerRequest({
    required String partnerId,
    required String venueId,
    required String date,
    String? time,
    String paymentMode = 'SELF_PAY',
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/nights/requests',
        body: {
          'hostId': userId,
          'partnerId': partnerId,
          'venueId': venueId,
          'eventDate': date,
          'eventTime': time ?? '20:00',
          'paymentMode': paymentMode,
        },
      );
      final data = jsonDecode(response.body);
      clearBookingCache();
      notifyFeedNeedsRefresh();
      RealtimeSyncManager.instance.triggerLiveFeedSync();
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
    } catch (e) {
      debugPrint('sendNightPartnerRequest error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> initiateNightInvitePayment({
    required String venueId,
    required String date,
    String? time,
    required String paymentMode,
    List<String>? partnerIds,
    double? ticketPrice,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/nights/invite-payment/initiate',
        body: {
          'hostId': userId,
          'venueId': venueId,
          'eventDate': date,
          'eventTime': time ?? '20:00',
          'paymentMode': paymentMode,
          if (partnerIds != null && partnerIds.isNotEmpty)
            'partnerIds': partnerIds,
          if (ticketPrice != null && ticketPrice > 0)
            'ticketPrice': ticketPrice,
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (data['data'] != null && data['data'] is Map) {
          return Map<String, dynamic>.from(data['data']);
        }
        return Map<String, dynamic>.from(data);
      }
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (e) {
      debugPrint('initiateNightInvitePayment error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> verifyNightInvitePayment({
    String? partnerId,
    List<String>? partnerIds,
    required String venueId,
    required String date,
    String? time,
    required String paymentMode,
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? razorpaySignature,
    String paymentMethod = 'razorpay',
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final resolvedPartnerIds =
          partnerIds ?? (partnerId != null ? [partnerId] : <String>[]);
      final primaryPartnerId =
          partnerId ??
          (resolvedPartnerIds.isNotEmpty ? resolvedPartnerIds.first : '');
      final response = await post(
        '/api/mobile/nights/invite-payment/verify',
        body: {
          'hostId': userId,
          'partnerId': primaryPartnerId,
          if (resolvedPartnerIds.isNotEmpty) 'partnerIds': resolvedPartnerIds,
          'venueId': venueId,
          'eventDate': date,
          'eventTime': time ?? '20:00',
          'paymentMode': paymentMode,
          'razorpayOrderId': razorpayOrderId,
          'razorpayPaymentId': razorpayPaymentId,
          'razorpaySignature': razorpaySignature,
          'paymentMethod': paymentMethod,
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          (data is Map && data['success'] == true)) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerLiveFeedSync();
        if (data is Map<String, dynamic>) {
          return data;
        }
        return {'success': true};
      }
      return data is Map<String, dynamic>
          ? data
          : {'success': false, 'message': 'Verification failed'};
    } catch (e) {
      debugPrint('verifyNightInvitePayment error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<bool> respondToNightPartnerRequest({
    required String requestId,
    required String action, // 'accept' | 'decline'
    String? venueId,
    String? eventDate,
    String? hostId,
  }) async {
    final res = await respondToNightPartnerRequestDetailed(
      requestId: requestId,
      action: action,
      venueId: venueId,
      eventDate: eventDate,
      hostId: hostId,
    );
    return res['success'] == true;
  }

  static Future<Map<String, dynamic>> respondToNightPartnerRequestDetailed({
    required String requestId,
    required String action, // 'accept' | 'decline'
    // Event context. The live feed keys a night by venue + date, so the id it
    // holds is not always the request's own; these let the server fall back to
    // the caller's pending invite for that night instead of rejecting the call.
    String? venueId,
    String? eventDate,
    String? hostId,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'User not logged in'};
    }
    try {
      final cleanId = requestId
          .replaceAll('upcoming_night_timeline_', '')
          .replaceAll('party_plan_timeline_', '')
          .replaceAll('night_partner_', '')
          .replaceAll('party_plan_', '')
          .replaceAll('match_', '')
          .replaceAll('request_', '')
          .replaceAll('req_', '')
          .replaceAll('pending_bk_', '')
          .replaceAll('pending_pp_join_', '')
          .replaceAll('pending_pp_', '')
          .replaceAll('pending_gp_', '')
          .replaceAll('pending_sm_', '')
          .replaceAll('pending_', '')
          .replaceAll('solo_booking_', '')
          .replaceAll('bk_', '')
          .replaceAll('sm_', '')
          .replaceAll('gp_', '')
          .replaceAll('pp_', '')
          .trim();
      // The route needs a path segment. When the card could not produce a real
      // request id we send this placeholder: it fails the server's UUID check,
      // which is exactly what routes the call to the venue + date + host
      // resolution instead of rejecting it.
      final pathId = cleanId.isEmpty ? 'resolve' : cleanId;
      final response = await patch(
        '/api/mobile/nights/requests/$pathId',
        body: {
          'partnerId': userId,
          'action': action.toLowerCase(),
          if (venueId != null && venueId.isNotEmpty) 'venueId': venueId,
          if (eventDate != null && eventDate.isNotEmpty) 'eventDate': eventDate,
          if (hostId != null && hostId.isNotEmpty) 'hostId': hostId,
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 ||
          (data is Map && data['success'] == true)) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerLiveFeedSync();
        if (data is Map<String, dynamic>) {
          return data;
        }
        return {'success': true};
      }
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {
        'success': false,
        'message': data is Map
            ? (data['message'] ?? 'Failed to respond')
            : 'Failed to respond',
      };
    } catch (e) {
      debugPrint('respondToNightPartnerRequest error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> initiateMatchPayment({
    required String matchId,
    String paymentMode = 'SELF_PAY',
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final cleanId = matchId
          .replaceAll('upcoming_night_timeline_', '')
          .replaceAll('party_plan_timeline_', '')
          .replaceAll('night_partner_', '')
          .replaceAll('party_plan_', '')
          .replaceAll('match_', '')
          .replaceAll('request_', '')
          .replaceAll('req_', '')
          .replaceAll('pp_', '')
          .trim();
      final response = await post(
        '/api/mobile/nights/matches/$cleanId/pay',
        body: {'hostId': userId, 'paymentMode': paymentMode},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('initiateMatchPayment error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> verifyMatchPayment({
    required String matchId,
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? razorpaySignature,
    String paymentMethod = 'razorpay',
  }) async {
    try {
      final cleanId = matchId
          .replaceAll('upcoming_night_timeline_', '')
          .replaceAll('party_plan_timeline_', '')
          .replaceAll('night_partner_', '')
          .replaceAll('party_plan_', '')
          .replaceAll('match_', '')
          .replaceAll('request_', '')
          .replaceAll('req_', '')
          .replaceAll('pp_', '')
          .trim();
      final response = await post(
        '/api/mobile/nights/matches/$cleanId/verify',
        body: {
          'razorpay_order_id': razorpayOrderId ?? 'wallet_payment',
          'razorpay_payment_id': razorpayPaymentId ?? 'wallet_payment',
          'razorpay_signature': razorpaySignature ?? 'mock_signature',
          'paymentMethod': paymentMethod,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
          RealtimeSyncManager.instance.triggerLiveFeedSync();
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('verifyMatchPayment error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> cancelUpcomingNight({
    required String targetId,
    String reason = 'Change of plans',
    String? action,
  }) async {
    try {
      final cleanId = targetId
          .replaceAll('upcoming_night_timeline_', '')
          .replaceAll('party_plan_timeline_', '')
          .replaceAll('night_partner_', '')
          .replaceAll('party_plan_', '')
          .replaceAll('match_', '')
          .replaceAll('request_', '')
          .replaceAll('req_', '')
          .replaceAll('pp_', '')
          .trim();
      final Map<String, dynamic> requestBody = {'reason': reason};
      if (action != null) {
        requestBody['action'] = action;
      }
      final response = await post(
        '/api/mobile/nights/cancel/$cleanId',
        body: requestBody,
      );
      if (response.statusCode == 200) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        RealtimeSyncManager.instance.triggerLiveFeedSync();
        final data = jsonDecode(response.body);
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('cancelUpcomingNight error: $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> fetchEventPosts() async {
    try {
      final response = await get('/api/mobile/nights/event-posts');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchEventPosts error: $e');
    }
    return [];
  }

  // â”€â”€ Swipe Status & Subscription Limits â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns the current user's swipe action on [targetUserId] today,
  /// and the plan limits so the UI can enforce them without a server round-trip.
  /// Response: { alreadyLiked, alreadySuperLiked, dailyLikesLimit, dailyLikesUsed,
  ///             superlikesRemaining, superlikesPerCycle }
  static Future<Map<String, dynamic>> fetchSwipeStatus(
    String targetUserId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return {};
    try {
      final response = await get(
        '/api/mobile/user/swipe-status',
        queryParameters: {'userId': userId, 'targetUserId': targetUserId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchSwipeStatus error: $e');
    }
    return {};
  }

  static Future<Map<String, dynamic>?> backtrackSwipe(
    String targetUserId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/user/backtrack',
        body: {'userId': userId, 'targetUserId': targetUserId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final resData = Map<String, dynamic>.from(data['data'] ?? {});
          resData['success'] = true;
          return resData;
        }
      } else if (response.statusCode == 403) {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'limitReached': true,
          'message':
              data['message'] ??
              'You have reached your daily backtrack limit. Upgrade your plan to get more backtracks!',
        };
      }
    } catch (e) {
      debugPrint('backtrackSwipe error: $e');
    }
    return null;
  }

  /// Returns the current user's subscription summary:
  /// dailyLikesLimit, dailyLikesUsed, superlikesRemaining, superlikesPerCycle
  static Future<Map<String, dynamic>> fetchUserSubscription() async {
    final userId = currentUserId;
    if (userId == null) return {};
    try {
      final response = await get('/api/mobile/subscriptions/current');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchUserSubscription error: $e');
    }
    return {};
  }

  /// Returns the FULL subscription status in one call:
  /// tier, tierRank, planName, daily limits/usage, superlikes, boosts, feature flags.
  static Future<Map<String, dynamic>> fetchSubscriptionStatus() async {
    final userId = currentUserId;
    if (userId == null) return {};
    try {
      final response = await get('/api/mobile/subscriptions/status');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchSubscriptionStatus error: $e');
    }
    return {};
  }

  /// Fetches comprehensive VIP entitlements breakdown, usage, add-ons, and checklist
  static Future<Map<String, dynamic>> fetchEntitlementsSummary() async {
    final userId = currentUserId;
    if (userId == null) return {};
    try {
      final response = await get('/api/mobile/subscriptions/entitlements');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchEntitlementsSummary error: $e');
    }
    return {};
  }

  /// Fetches available Add-on packages catalog with in-memory caching (5-min TTL)
  static Future<List<Map<String, dynamic>>> fetchAvailableAddons({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedAddonPackages != null &&
        _cachedAddonPackages!.isNotEmpty &&
        _addonPackagesCacheTime != null &&
        DateTime.now().difference(_addonPackagesCacheTime!) <
            const Duration(minutes: 5)) {
      return _cachedAddonPackages!;
    }
    try {
      final response = await get('/api/mobile/subscriptions/addons');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final list = List<Map<String, dynamic>>.from(data['data']);
          if (list.isNotEmpty) {
            _cachedAddonPackages = list;
            _addonPackagesCacheTime = DateTime.now();
            return list;
          }
        }
      }
    } catch (e) {
      debugPrint('fetchAvailableAddons error: $e');
    }
    if (_cachedAddonPackages != null && _cachedAddonPackages!.isNotEmpty) {
      return _cachedAddonPackages!;
    }
    // Reliable default catalog so add-on store always renders instantly
    return const [
      {
        'id': '712d2b51-04b1-47fc-ac31-12a214a837b8',
        'name': '+5 Super Likes',
        'featureKey': 'superlike',
        'feature_key': 'superlike',
        'quantity': 5,
        'price': 99.0,
        'currency': 'INR',
        'badge': 'POPULAR',
        'description':
            'Stand out and connect instantly with 5 priority Super Likes.',
        'displayOrder': 1,
        'display_order': 1,
        'isActive': true,
        'is_active': true,
      },
      {
        'id': '150ce90d-d356-4cb7-b801-65501aa2455d',
        'name': '+15 Super Likes',
        'featureKey': 'superlike',
        'feature_key': 'superlike',
        'quantity': 15,
        'price': 249.0,
        'currency': 'INR',
        'badge': 'BEST VALUE',
        'description':
            'Triple your connections with 15 Super Likes at huge savings.',
        'displayOrder': 2,
        'display_order': 2,
        'isActive': true,
        'is_active': true,
      },
      {
        'id': '01a67a88-5ce5-43b3-a900-87ac24e115c4',
        'name': '+1 Profile Boost',
        'featureKey': 'profile_boost',
        'feature_key': 'profile_boost',
        'quantity': 1,
        'price': 49.0,
        'currency': 'INR',
        'badge': 'LIGHTNING',
        'description':
            'Get up to 10x more profile views with a 30-minute spotlight.',
        'displayOrder': 3,
        'display_order': 3,
        'isActive': true,
        'is_active': true,
      },
      {
        'id': 'f6019794-ca8e-4b13-b9aa-60c237d1bd56',
        'name': '+3 Profile Boosts',
        'featureKey': 'profile_boost',
        'feature_key': 'profile_boost',
        'quantity': 3,
        'price': 129.0,
        'currency': 'INR',
        'badge': 'POPULAR',
        'description':
            '3 profile boosts to dominate the weekend nightlife scene.',
        'displayOrder': 4,
        'display_order': 4,
        'isActive': true,
        'is_active': true,
      },
      {
        'id': '6326f437-d869-401e-bf17-d37a885071cb',
        'name': '+5 Party Plans',
        'featureKey': 'party_creation',
        'feature_key': 'party_creation',
        'quantity': 5,
        'price': 199.0,
        'currency': 'INR',
        'badge': 'EXCLUSIVE',
        'description':
            'Host 5 additional epic party plans without upgrading your plan.',
        'displayOrder': 5,
        'display_order': 5,
        'isActive': true,
        'is_active': true,
      },
      {
        'id': 'a9522a2d-e727-4fb3-9ff8-f5700417170d',
        'name': '+10 Backtracks',
        'featureKey': 'backtrack',
        'feature_key': 'backtrack',
        'quantity': 10,
        'price': 49.0,
        'currency': 'INR',
        'badge': 'POPULAR',
        'description':
            'Undo up to 10 left swipes and get a second chance to connect.',
        'displayOrder': 6,
        'display_order': 6,
        'isActive': true,
        'is_active': true,
      },
    ];
  }

  /// Activates a 30-minute Profile Boost
  static Future<Map<String, dynamic>> useBoost() async {
    try {
      final response = await post('/api/mobile/subscriptions/use-boost', body: {});
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'message': 'Profile boost processed',
      };
    } catch (e) {
      debugPrint('useBoost error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Purchases an Add-on using Smart Credit Wallet
  static Future<Map<String, dynamic>> purchaseAddonWithWallet(
    String addonPackageId, {
    int count = 1,
  }) async {
    try {
      final response = await post(
        '/api/mobile/subscriptions/addons/pay-wallet',
        body: {'addonPackageId': addonPackageId, 'count': count},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cachedAddonPackages = null;
        _addonPackagesCacheTime = null;
      }
      return data is Map<String, dynamic>
          ? data
          : {'success': false, 'message': 'Unknown response'};
    } catch (e) {
      debugPrint('purchaseAddonWithWallet error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Creates a Razorpay Order for an Add-on package
  static Future<Map<String, dynamic>?> createAddonRazorpayOrder(
    String addonPackageId,
  ) async {
    try {
      final response = await post(
        '/api/mobile/subscriptions/addons/create-order',
        body: {'addonPackageId': addonPackageId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('createAddonRazorpayOrder error: $e');
    }
    return null;
  }

  /// Verifies Razorpay payment for an Add-on package
  static Future<Map<String, dynamic>> verifyAddonRazorpayPayment({
    required String addonPackageId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final response = await post(
        '/api/mobile/subscriptions/addons/purchase',
        body: {
          'addonPackageId': addonPackageId,
          'gatewayOrderId': razorpayOrderId,
          'gatewayPaymentId': razorpayPaymentId,
          'razorpaySignature': razorpaySignature,
        },
      );
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic>
          ? data
          : {'success': false, 'message': 'Verification failed'};
    } catch (e) {
      debugPrint('verifyAddonRazorpayPayment error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>?> createGroupParty({
    required String venueId,
    required int numberOfFriends,
    required String partyDate,
    required String mobileNumber,
    String? optionalMobileNumber,
    String? foodPreference,
    String? drinkPreference,
    String? partySubject,
    String? partyRequirement,
    String? partyDescription,
    String? startTime,
    String? paymentMode,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/group-parties',
        timeout: transactionalTimeout,
        body: {
          'userId': userId,
          'venueId': venueId,
          'numberOfFriends': numberOfFriends,
          'partyDate': partyDate,
          'mobileNumber': mobileNumber.trim(),
          if (optionalMobileNumber != null &&
              optionalMobileNumber.trim().isNotEmpty)
            'optionalMobileNumber': optionalMobileNumber.trim(),
          if (foodPreference != null && foodPreference.trim().isNotEmpty)
            'foodPreference': foodPreference.trim(),
          if (drinkPreference != null && drinkPreference.trim().isNotEmpty)
            'drinkPreference': drinkPreference.trim(),
          if (partySubject != null && partySubject.trim().isNotEmpty)
            'partySubject': partySubject.trim(),
          if (partyRequirement != null && partyRequirement.trim().isNotEmpty)
            'partyRequirement': partyRequirement.trim(),
          if (partyDescription != null && partyDescription.trim().isNotEmpty)
            'partyDescription': partyDescription.trim(),
          if (startTime != null && startTime.trim().isNotEmpty)
            'startTime': startTime.trim(),
          if (paymentMode != null && paymentMode.trim().isNotEmpty)
            'paymentMode': paymentMode.trim(),
        },
      );
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          if (data['success'] == true) {
            clearBookingCache();
            notifyFeedNeedsRefresh();
          }
          return data;
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('createGroupParty error: $e');
    }
    return null;
  }

  static Future<bool> verifyGroupPartyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    String? partyId,
  }) async {
    try {
      final response = await post(
        '/api/mobile/group-parties/verify',
        timeout: transactionalTimeout,
        body: {
          'razorpay_order_id': razorpayOrderId,
          'razorpay_payment_id': razorpayPaymentId,
          'razorpay_signature': razorpaySignature,
          if (partyId != null && partyId.isNotEmpty) 'partyId': partyId,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
          return true;
        }
        return false;
      }
    } catch (e) {
      debugPrint('verifyGroupPartyPayment error: $e');
    }
    return false;
  }

  static Future<bool> cancelPendingGroupParty(String groupPartyId) async {
    try {
      final response = await post(
        '/api/mobile/group-parties/cancel-pending',
        body: {'partyId': groupPartyId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
          return true;
        }
      }
    } catch (e) {
      debugPrint('cancelPendingGroupParty error: $e');
    }
    return false;
  }

  static Future<bool> cancelPendingBooking(String bookingId) async {
    try {
      final response = await post(
        '/api/mobile/bookings/cancel-pending',
        body: {'bookingId': bookingId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
          return true;
        }
      }
    } catch (e) {
      debugPrint('cancelPendingBooking error: $e');
    }
    return false;
  }

  /// Fetches authoritative cancellation policy breakdown & refund amounts
  static Future<Map<String, dynamic>?> fetchBookingCancellationPreview(
    String bookingId, {
    bool isGroupParty = false,
  }) async {
    try {
      final cleanId = cleanBookingId(bookingId);
      final path = isGroupParty
          ? '/api/mobile/group-parties/$cleanId/cancellation-preview'
          : '/api/mobile/bookings/$cleanId/cancellation-preview';
      final response = await get(path);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      } else {
        final data = jsonDecode(response.body);
        return {
          'error': data['message'] ?? 'Failed to load cancellation preview',
        };
      }
    } catch (e) {
      debugPrint('fetchBookingCancellationPreview error: $e');
    }
    return null;
  }

  /// Confirms booking cancellation and initiates refund (Wallet if <= 1500, UPI/Bank if > 1500)
  static Future<Map<String, dynamic>?> confirmBookingCancellation(
    String bookingId, {
    bool isGroupParty = false,
    String? reason,
    Map<String, dynamic>? payoutDetails,
  }) async {
    try {
      final cleanId = cleanBookingId(bookingId);
      final path = isGroupParty
          ? '/api/mobile/group-parties/$cleanId/cancel'
          : '/api/mobile/bookings/$cleanId/cancel';
      final Map<String, dynamic> body = {
        'reason': reason ?? 'Cancelled by user',
      };
      if (payoutDetails != null) {
        body['payoutDetails'] = payoutDetails;
        body.addAll(payoutDetails);
      }
      final response = await post(path, body: body);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        clearBookingCache();
        notifyFeedNeedsRefresh();
        return Map<String, dynamic>.from(data);
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Cancellation failed',
        };
      }
    } catch (e) {
      debugPrint('confirmBookingCancellation error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Fetches universal booking & cancellation policies (Solo & Small Group Party)
  static Future<Map<String, dynamic>?> fetchBookingPolicies() async {
    try {
      final response = await get('/api/mobile/bookings/policy');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchBookingPolicies error: $e');
    }
    return null;
  }

  // â”€â”€ Subscription API Methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<List<dynamic>> fetchSubscriptionPackages({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedSubscriptionPackages != null &&
        _subscriptionPackagesCacheTime != null &&
        DateTime.now().difference(_subscriptionPackagesCacheTime!) <
            const Duration(minutes: 5)) {
      return _cachedSubscriptionPackages!;
    }
    try {
      final response = await get('/api/mobile/subscriptions/packages');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final list = List<dynamic>.from(data['data']);
          _cachedSubscriptionPackages = list;
          _subscriptionPackagesCacheTime = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('fetchSubscriptionPackages error: $e');
    }
    return _cachedSubscriptionPackages ?? [];
  }

  static Future<Map<String, dynamic>?> createSubscriptionOrder(
    String packageId,
  ) async {
    try {
      final response = await post(
        '/api/mobile/subscriptions/create-order',
        body: {'packageId': packageId},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('createSubscriptionOrder error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>> purchaseSubscription({
    required String packageId,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String razorpaySignature,
    String paymentMethod = 'razorpay',
  }) async {
    try {
      final response = await post(
        '/api/mobile/subscriptions/purchase',
        body: {
          'packageId': packageId,
          'gatewayOrderId': gatewayOrderId,
          'gatewayPaymentId': gatewayPaymentId,
          'razorpay_signature': razorpaySignature,
          'paymentMethod': paymentMethod,
        },
      );

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201
            ? (data['success'] ?? true)
            : false,
        'message': data['message'] ?? 'Failed to activate subscription.',
        'data': data['data'] ?? data,
        'statusCode': response.statusCode,
      };
    } catch (e) {
      debugPrint('purchaseSubscription error: $e');
      return {
        'success': false,
        'message': 'Network error occurred while verifying payment: $e',
        'statusCode': 500,
      };
    }
  }

  static Future<Map<String, dynamic>?> createBoostOrder(int boostCount) async {
    try {
      final response = await post(
        '/api/mobile/subscriptions/create-boost-order',
        body: {'boostCount': boostCount},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('createBoostOrder error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> payBoostWithWallet({
    required int boostCount,
    required double price,
  }) async {
    try {
      final response = await post(
        '/api/mobile/wallet/pay-boost',
        body: {'count': boostCount, 'boostCount': boostCount, 'price': price},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return Map<String, dynamic>.from(data);
      } else {
        final data = jsonDecode(response.body);
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('payBoostWithWallet error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>> purchaseBoost({
    required int boostCount,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final response = await post(
        '/api/mobile/subscriptions/purchase-boost',
        body: {
          'boostCount': boostCount,
          'gatewayOrderId': gatewayOrderId,
          'gatewayPaymentId': gatewayPaymentId,
          'razorpay_signature': razorpaySignature,
        },
      );

      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201
            ? (data['success'] ?? true)
            : false,
        'message': data['message'] ?? 'Failed to purchase boosts.',
        'data': data['data'] ?? data,
        'statusCode': response.statusCode,
      };
    } catch (e) {
      debugPrint('purchaseBoost error: $e');
      return {
        'success': false,
        'message': 'Network error occurred while verifying payment: $e',
        'statusCode': 500,
      };
    }
  }

  /// Fetches all subscription transactions for the current user
  static Future<List<Map<String, dynamic>>> fetchSubscriptionHistory({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await get(
        '/api/mobile/subscriptions/history',
        queryParameters: {'page': page.toString(), 'limit': limit.toString()},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final txns = data['data']['transactions'] as List? ?? [];
          return txns.map((t) => Map<String, dynamic>.from(t)).toList();
        }
      }
    } catch (e) {
      debugPrint('fetchSubscriptionHistory error: $e');
    }
    return [];
  }

  /// Fetches actual purchased subscription plans (ACTIVE, UPCOMING, EXPIRED)
  static Future<List<Map<String, dynamic>>> fetchUserSubscriptions() async {
    try {
      final response = await get('/api/mobile/subscriptions/plans');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final plans = data['data'] as List? ?? [];
          return plans.map((p) => Map<String, dynamic>.from(p)).toList();
        }
      }
    } catch (e) {
      debugPrint('fetchUserSubscriptions error: $e');
    }
    return [];
  }

  static Future<bool> submitSafetyCheck({
    required String partnerId,
    required bool feltSafe,
    List<String>? prebuiltAnswers,
    String? opinion,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await post(
        '/api/mobile/user/safety-check',
        body: {
          'userId': userId,
          'partnerId': partnerId,
          'feltSafe': feltSafe,
          'prebuiltAnswers': prebuiltAnswers ?? [],
          'opinion': opinion ?? '',
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('submitSafetyCheck error: $e');
    }
    return false;
  }

  // â”€â”€ Admin helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Admin: Force-expire a user's active subscription immediately
  static Future<bool> adminForceExpireSubscription(
    String userId, {
    String? reason,
  }) async {
    try {
      final response = await patch(
        '/api/admin/subscriptions/users/$userId/force-expire',
        body: {'reason': reason ?? 'Admin action'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('adminForceExpireSubscription error: $e');
    }
    return false;
  }

  /// Admin: Extend a user's active subscription by N days
  static Future<Map<String, dynamic>?> adminExtendSubscription(
    String userId, {
    required int days,
    String? reason,
  }) async {
    try {
      final response = await patch(
        '/api/admin/subscriptions/users/$userId/extend',
        body: {'days': days, 'reason': reason ?? 'Admin extension'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('adminExtendSubscription error: $e');
    }
    return null;
  }

  /// Fetch full ticket data for a party plan request (host + joiner profiles, ticketCode, expiresAt)
  static Future<Map<String, dynamic>?> fetchPartyPlanTicket(
    String reqId,
  ) async {
    try {
      final response = await get(
        '/api/mobile/party-plans/requests/$reqId/ticket',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
      debugPrint(
        'fetchPartyPlanTicket failed [${response.statusCode}]: ${response.body}',
      );
    } catch (e) {
      debugPrint('fetchPartyPlanTicket error: $e');
    }
    return null;
  }

  /// One-Time Face Verification via Azure AI Face Service
  static Future<Map<String, dynamic>> verifyFace({
    required String selfiePath,
    required String profilePhotoPath,
  }) async {
    try {
      final Uint8List selfieBytes = await XFile(selfiePath).readAsBytes();
      final Uint8List profileBytes = await XFile(
        profilePhotoPath,
      ).readAsBytes();

      if (selfieBytes.isEmpty || profileBytes.isEmpty) {
        return {
          'success': false,
          'verified': false,
          'message': 'Image files could not be read.',
        };
      }

      final String selfieBase64 = base64Encode(selfieBytes);
      final String profileBase64 = base64Encode(profileBytes);

      final response = await post(
        '/api/mobile/auth/verify-face',
        body: {'selfie': selfieBase64, 'profilePhoto': profileBase64},
      );

      final data = jsonDecode(response.body);
      return {
        'success': data['success'] == true,
        'verified': data['verified'] == true,
        'confidence': (data['confidence'] ?? 0.0).toDouble(),
        'message': data['message'] ?? 'Face verification completed',
      };
    } catch (e) {
      debugPrint('verifyFace error: $e');
      return {
        'success': false,
        'verified': false,
        'message': 'Network error connecting to Azure Face Verification: $e',
      };
    }
  }

  /// Single Image Human Face Detection
  static Future<Map<String, dynamic>> detectFace(String imagePath) async {
    try {
      final Uint8List imageBytes = await XFile(imagePath).readAsBytes();
      if (imageBytes.isEmpty) {
        return {
          'success': false,
          'hasFace': false,
          'message': 'Image file could not be read.',
        };
      }

      final String imageBase64 = base64Encode(imageBytes);

      final response = await post(
        '/api/mobile/auth/detect-face',
        body: {'image': imageBase64},
      );

      final data = jsonDecode(response.body);
      return {
        'success': data['success'] == true,
        'hasFace': data['hasFace'] == true,
        'faceCount': data['faceCount'] ?? 0,
        'message': data['message'] ?? 'Face detection completed',
      };
    } catch (e) {
      debugPrint('detectFace error: $e');
      return {
        'success': false,
        'hasFace': false,
        'message': 'Network error connecting to Face Detection service: $e',
      };
    }
  }

  /// Permanently soft-delete the user's account and perform full session cleanup
  static Future<Map<String, dynamic>> deleteAccount({
    required String password,
    String? reason,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {
        'success': false,
        'message': 'Authentication required. Please log in again.',
      };
    }

    try {
      final response = await post(
        '/api/mobile/user/delete-account',
        body: {'userId': userId, 'password': password, 'reason': reason ?? ''},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await logout();
        return {
          'success': true,
          'message': data['message'] ?? 'Account deleted successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to delete account',
          'code': data['code'],
        };
      }
    } catch (e) {
      debugPrint('deleteAccount error: $e');
      return {'success': false, 'message': 'Network error deleting account'};
    }
  }

  // â”€â”€ Ticket System Methods & Internal Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Map<String, String> get _authHeaders {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (!kIsWeb) 'Accept-Encoding': 'gzip, deflate',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  static Future<http.Response> _get(String path, {Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    final inFlightKey = uri.toString();
    if (_inFlightGets.containsKey(inFlightKey)) {
      return await _inFlightGets[inFlightKey]!;
    }
    final future = () async {
      // Mirrors the connection-stall retry in [get]: a lost SYN fails fast via
      // [_connectTimeout], and a fresh socket almost always connects at once.
      for (var attempt = 1; ; attempt++) {
        try {
          final res = await _httpClient
              .get(uri, headers: _authHeaders)
              .timeout(timeout ?? defaultTimeout);
          _checkAutoblockedResponse(res);
          return res;
        } on SocketException {
          if (attempt >= 2) rethrow;
          debugPrint(
            '[ApiService] GET $uri could not connect on attempt $attempt, retrying on a new socket...',
          );
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    }();
    _inFlightGets[inFlightKey] = future;
    try {
      return await future;
    } finally {
      _inFlightGets.remove(inFlightKey);
    }
  }

  static Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _httpClient
        .post(uri, headers: _authHeaders, body: jsonEncode(body))
        .timeout(timeout ?? defaultTimeout);
    _checkAutoblockedResponse(res);
    return res;
  }

  /// Fetch user tickets with tab filtering ('upcoming', 'active', 'used', 'expired', 'cancelled')
  static Future<List<Map<String, dynamic>>> getUserTickets({
    String tab = 'all',
  }) async {
    final userId = currentUserId ?? '';
    if (userId.isEmpty) return [];
    try {
      final response = await _get(
        '/api/mobile/tickets?userId=$userId&tab=$tab',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('getUserTickets error: $e');
    }
    return [];
  }

  /// Get single ticket details by ID
  static Future<Map<String, dynamic>?> getTicketById(String id) async {
    final userId = currentUserId ?? '';
    try {
      final response = await _get('/api/mobile/tickets/$id?userId=$userId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('getTicketById error: $e');
    }
    return null;
  }

  /// Get a secure time-limited download URL for a ticket PDF
  static Future<Map<String, dynamic>> getTicketDownloadUrl(
    String ticketId,
  ) async {
    final userId = currentUserId ?? '';
    try {
      final response = await _get(
        '/api/mobile/tickets/$ticketId/download-url?userId=$userId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
      return {'success': false, 'message': 'Failed to get download URL'};
    } catch (e) {
      debugPrint('getTicketDownloadUrl error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Create a shareable token for a ticket (returns shareText for WhatsApp/clipboard)
  static Future<Map<String, dynamic>> createTicketShareToken(
    String ticketId,
  ) async {
    final userId = currentUserId ?? '';
    try {
      final response = await _post(
        '/api/mobile/tickets/$ticketId/share-token',
        {'userId': userId},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
      return {'success': false, 'message': 'Failed to create share token'};
    } catch (e) {
      debugPrint('createTicketShareToken error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // â”€â”€ Safety Check Methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Submit the user's safety check status for a live Party Plan session
  static Future<Map<String, dynamic>> submitSafetyCheckStatus({
    required String checkId,
    required String safetyStatus,
    String? notes,
    double? locationLat,
    double? locationLng,
  }) async {
    try {
      final body = <String, dynamic>{
        'safetyStatus': safetyStatus,
        'notes': notes ?? '',
      };
      if (locationLat != null) body['locationLat'] = locationLat;
      if (locationLng != null) body['locationLng'] = locationLng;
      final response = await _post(
        '/api/mobile/party-plans/safety-checks/$checkId/respond',
        body,
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('submitSafetyCheckStatus error: $e');
      return {'success': false, 'message': 'Failed to submit safety check'};
    }
  }

  static Map<String, dynamic>? _cachedSafetyCheck;
  static DateTime? _safetyCheckCacheTime;

  /// Fetch pending/unanswered safety check for current user.
  ///
  /// This is one of the five calls the Live Feed awaits together, and it was the
  /// only one with no cache at all — so however well the other four were cached,
  /// `Future.wait` could never finish faster than a full round trip and the feed
  /// could never render quickly. Worse, every socket event that failed to match
  /// an entity fell back to a full feed reload, paying this round trip again,
  /// which is what made notification cards update late.
  ///
  /// The window matches the notifications cache so the two stay in step. A
  /// pending safety check also arrives over the socket, so this being briefly
  /// stale never hides one from the user.
  static Future<Map<String, dynamic>?> fetchPendingSafetyCheck({
    bool forceRefresh = false,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final now = DateTime.now();
    if (!forceRefresh &&
        _safetyCheckCacheTime != null &&
        now.difference(_safetyCheckCacheTime!).inSeconds < 20) {
      return _cachedSafetyCheck;
    }

    try {
      final response = await _get(
        '/api/mobile/party-plans/safety-checks/pending?userId=$userId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _safetyCheckCacheTime = DateTime.now();
        if (data['success'] == true && data['data'] != null) {
          _cachedSafetyCheck = Map<String, dynamic>.from(data['data']);
          return _cachedSafetyCheck;
        }
        // A successful "nothing pending" is a real answer worth caching, or the
        // feed would keep asking on every single refresh.
        _cachedSafetyCheck = null;
        return null;
      }
    } catch (e) {
      debugPrint('fetchPendingSafetyCheck error: $e');
    }
    return _cachedSafetyCheck;
  }

  // â”€â”€ Current User Helper (async) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns the currently logged-in userId as a Future (nullable String)
  static Future<String?> getCurrentUserId() async {
    return currentUserId;
  }

  // â”€â”€ Party Plan Mutual Cancellation Methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Request to cancel a confirmed Party Plan (mutual cancellation flow)
  static Future<Map<String, dynamic>> requestPartyPlanCancellation({
    required String planId,
    required String reason,
    String? otherReasonText,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }
    try {
      final body = <String, dynamic>{'userId': userId, 'reason': reason};
      if (otherReasonText != null && otherReasonText.isNotEmpty) {
        body['otherReasonText'] = otherReasonText;
      }
      final response = await _post(
        // Mutual cancellation belongs to the Party Plan controller mounted at
        // /api/mobile/plans (not the request-management route namespace).
        '/api/mobile/plans/$planId/cancellation-request',
        body,
      );
      final resData = jsonDecode(response.body) as Map<String, dynamic>;
      if (resData['success'] == true) {
        notifyFeedNeedsRefresh();
      }
      return resData;
    } catch (e) {
      debugPrint('requestPartyPlanCancellation error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Fetch the active cancellation request state for a Party Plan
  static Future<Map<String, dynamic>?> getPartyPlanCancellationRequest(
    String planId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await _get(
        '/api/mobile/plans/$planId/cancellation-request?userId=$userId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
    } catch (e) {
      debugPrint('getPartyPlanCancellationRequest error: $e');
    }
    return null;
  }

  /// Approve or reject a received cancellation request
  /// Answers the 24-hour "no partner yet" prompt on an event-linked plan.
  ///
  /// [action] is one of `keep`, `solo` or `cancel`. The server decides what each
  /// one costs and refunds — this only reports the choice and hands back the
  /// authoritative result for the card to reconcile against.
  static Future<Map<String, dynamic>> respondToEventPlanNoMatch({
    required String planId,
    required String action,
    String? reason,
  }) async {
    final cleanId = cleanBookingId(planId);
    try {
      final response = await post(
        '/api/mobile/party-plans/$cleanId/no-match-response',
        body: {
          'action': action.toLowerCase(),
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
        timeout: transactionalTimeout,
      );
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        if (data['success'] == true) {
          clearBookingCache();
          notifyFeedNeedsRefresh();
        }
        return data;
      }
      return {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      debugPrint('respondToEventPlanNoMatch error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> respondToPartyPlanCancellationRequest({
    required String planId,
    required String requestId,
    required String action,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }
    final cleanPlanId = planId.replaceFirst(
      RegExp(r'^(pp_|party_plan_|party_plan_timeline_)', caseSensitive: false),
      '',
    );
    try {
      final response = await _post(
        '/api/mobile/plans/$cleanPlanId/cancellation-request/respond',
        {'userId': userId, 'requestId': requestId, 'action': action},
      );
      final resData = jsonDecode(response.body) as Map<String, dynamic>;
      if (resData['success'] == true) {
        notifyFeedNeedsRefresh();
      }
      return resData;
    } catch (e) {
      debugPrint('respondToPartyPlanCancellationRequest error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> confirmArrival({
    required String planId,
    required String userId,
    required bool hasArrived,
    String stage = 'thirty_min_reach',
    String source = 'LIVE_FEED',
    String? notificationId,
  }) async {
    try {
      final cleanPlanId = planId.replaceFirst(
        RegExp(
          r'^(pp_|party_plan_|party_plan_timeline_)',
          caseSensitive: false,
        ),
        '',
      );
      final response = await _post(
        '/api/mobile/party-plans/$cleanPlanId/confirm-arrival',
        {
          'userId': userId,
          'planId': cleanPlanId,
          'hasArrived': hasArrived,
          'response': hasArrived ? 'YES' : 'NO',
          'stage': stage,
          'source': source,
          // ignore: use_null_aware_elements
          if (notificationId != null) 'notificationId': notificationId,
        },
      );
      final dynamic body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return body;
      }
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
      };
    } catch (e) {
      debugPrint('confirmArrival error: $e');
      return {'success': false, 'message': '$e'};
    }
  }

  static Future<Map<String, dynamic>> getPartyPlanReachStatus(
    String planId,
  ) async {
    try {
      final cleanPlanId = planId.replaceFirst(
        RegExp(
          r'^(pp_|party_plan_|party_plan_timeline_)',
          caseSensitive: false,
        ),
        '',
      );
      final response = await _get(
        '/api/mobile/party-plans/$cleanPlanId/reach-status',
      );
      final dynamic body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return body;
      }
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
      };
    } catch (e) {
      debugPrint('getPartyPlanReachStatus error: $e');
      return {'success': false, 'message': '$e'};
    }
  }

  static Future<Map<String, dynamic>> submitPartyReview({
    required String planId,
    required String reviewerId,
    required int rating,
    String? comment,
    bool isReported = false,
    String? reportReason,
  }) async {
    try {
      final response = await _post('/api/mobile/party-plans/$planId/review', {
        'reviewerId': reviewerId,
        'rating': rating,
        'comment': comment,
        'isReported': isReported,
        'reportReason': reportReason,
      });
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('submitPartyReview error: $e');
      return {'success': false, 'message': '$e'};
    }
  }
}

// â”€â”€ Party Plan Request Result â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class PartyPlanRequestResult {
  final bool success;
  final bool alreadyRequested;
  final bool isNewRequest;
  final String message;
  final String? requestId;
  final String? status;
  final Map<String, dynamic>? rawData;

  PartyPlanRequestResult({
    required this.success,
    required this.alreadyRequested,
    required this.isNewRequest,
    required this.message,
    this.requestId,
    this.status,
    this.rawData,
  });
}
