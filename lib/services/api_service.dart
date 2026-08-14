import 'dart:io' show Platform;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
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
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'notification_navigator.dart';
import 'push_notification_service.dart';
import '../screens/auth/autoblocked_warning_screen.dart';

class ApiService {
  // Toggle this to true to use your local backend, false for production
  static const bool isLocal = false;

  // Uses your machine's local IP (192.168.0.150) for local dev on a real device
  static String get baseUrl {
    if (!isLocal) {
      return 'https://lunara-api-server-a8gfdvg0hjdec6gx.centralindia-01.azurewebsites.net';
    }
    if (kIsWeb) {
      return 'http://localhost:9076';
    }
    return 'http://192.168.0.150:9076';
  }

  static String? _authToken;
  static String? selectedCity;
  static User? cachedCurrentUser;

  static final ValueNotifier<int> profileUpdateNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> planPostedNotifier = ValueNotifier<int>(0);

  // ── Synchronous Local Request Status Cache for Instant UI Rendering ────────
  static final Set<String> _cachedRequestedPlanIds = {};
  static final Map<String, Map<String, dynamic>> _cachedPartyPlanRequests = {};
  static String? _localStateUserId;

  /// Changes to the signed-in account must never reuse device-local activity
  /// state from the previous account. Server data remains the source of truth.
  static final ValueNotifier<int> authSessionNotifier = ValueNotifier<int>(0);

  static String _userPreferenceKey(String base, String userId) => '$base.$userId';

  static void _ensureLocalStateForCurrentUser() {
    final userId = currentUserId;
    if (_localStateUserId == userId) return;

    _localStateUserId = userId;
    _cachedRequestedPlanIds.clear();
    _cachedPartyPlanRequests.clear();
    localReadNotificationIds.clear();
    localReadRequestIds.clear();
    _readIdsLoaded = false;
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

  /// Mark a party plan as requested locally for instant UI responsiveness.
  static void markPartyPlanAsRequestedLocal(String planId, [Map<String, dynamic>? requestData]) {
    _ensureLocalStateForCurrentUser();
    if (planId.isEmpty) return;
    _cachedRequestedPlanIds.add(planId);
    _cachedPartyPlanRequests[planId] = requestData ?? {
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
        : prefs.getString(_userPreferenceKey('cached_requested_plan_ids', userId));
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
    }
  }

  static socket_io.Socket? socket;
  static final Map<String, List<Function(dynamic)>> _socketListeners = {};

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
      // Re-bind all registered listeners
      _socketListeners.forEach((event, callbacks) {
        for (final cb in callbacks) {
          socket!.on(event, cb);
        }
      });
    });

    socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
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
    if (previousUserId != currentUserId) authSessionNotifier.value++;

    final prefs = await SharedPreferences.getInstance();
    if (token != null && token.trim().isNotEmpty) {
      await prefs.setString('auth_token', token.trim());
      await loadLocalReadIds();
      initSocket();
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
    await clearAuthToken();
  }

  static Future<void> setSelectedCity(String city) async {
    selectedCity = city;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_city', city);
  }

  static String? get authToken => _authToken;

  static Future<User?> fetchProfile({String? userId}) async {
    try {
      if (_authToken == null) {
        await initAuthToken();
      }
      String? targetUserId = userId;
      if (targetUserId == 'undefined' || targetUserId == 'null' || (targetUserId != null && targetUserId.trim().isEmpty)) {
        targetUserId = null;
      }
      targetUserId ??= currentUserId ?? cachedCurrentUser?.id;

      final Map<String, String> queryParams = {};
      if (targetUserId != null && targetUserId != 'undefined' && targetUserId != 'null' && targetUserId.trim().isNotEmpty) {
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
          if (userId == null || userId == currentUserId || (cachedCurrentUser != null && user.id == cachedCurrentUser!.id) || cachedCurrentUser == null) {
            cachedCurrentUser = user;
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

  static Future<List<Venue>> fetchVenues({String? city}) async {
    try {
      final targetCity = city ?? selectedCity;
      final path = (targetCity != null && targetCity.isNotEmpty)
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
            return list;
          }
        }
      }
      // Fallback: if we queried a specific city and got no venues, try fetching all venues
      if (targetCity != null && targetCity.isNotEmpty) {
        debugPrint(
          'fetchVenues: No venues found for $targetCity, falling back to all venues.',
        );
        final fallbackResponse = await get('/api/venues');
        if (fallbackResponse.statusCode == 200) {
          final data = jsonDecode(fallbackResponse.body);
          if (data['success'] == true && data['venues'] != null) {
            return (data['venues'] as List)
                .map((json) => Venue.fromJson(json))
                .toList();
          }
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching venues: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchActiveAds({
    String? city,
    String? type,
  }) async {
    try {
      final targetCity = city ?? selectedCity;
      final queryParams = <String>[];
      if (targetCity != null && targetCity.isNotEmpty) {
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
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching active ads: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchCustomers({String? city}) async {
    try {
      final userId = currentUserId;
      final Map<String, String> params = {};
      if (userId != null) params['currentUserId'] = userId;
      // Pass city to backend so it uses ILIKE (case-insensitive, partial match)
      final String? cityToFilter = city ?? selectedCity;
      if (cityToFilter != null && cityToFilter.isNotEmpty) {
        params['city'] = cityToFilter;
      }
      final response = await get(
        '/api/mobile/user/customers',
        queryParameters: params.isNotEmpty ? params : null,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Be flexible with the key name (customers or data)
        final dynamic list = data['customers'] ?? data['data'];
        if (list != null && list is List) {
          return List<Map<String, dynamic>>.from(list);
        } else if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching customers: $e');
      return [];
    }
  }

  static Future<List<Package>> fetchVenuePackages(String venueId) async {
    try {
      final response = await get(
        '/api/mobile/bookings/venues/$venueId/packages',
      );
      //debugPrint('Packages Response Status: ${response.statusCode}');
      //debugPrint('Packages Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        // The API returns packages in the 'data' field or 'packages' field
        final dynamic packageList =
            jsonResponse['data'] ?? jsonResponse['packages'];

        if (packageList is List) {
          return packageList.map((json) => Package.fromJson(json)).toList();
        } else if (jsonResponse is List) {
          return jsonResponse.map((json) => Package.fromJson(json)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching venue packages: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchPartyPlans({
    int page = 1,
    int limit = 20,
    String status = 'active',
  }) async {
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
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching party plans: $e');
      return [];
    }
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
          final msg = data['message'] ?? data['error'] ?? 'Failed to submit request';
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

  static Future<List<dynamic>?> fetchBookings() async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final response = await get(
        '/api/mobile/bookings',
        queryParameters: {'userId': userId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'] as List<dynamic>;
        }
      }
    } catch (e) {
      debugPrint('fetchBookings error: $e');
    }
    return null;
  }

  /// Fetches only the current user's large-party (group party) booking requests.
  /// Returns them as a typed list sorted newest-first.
  static Future<List<Map<String, dynamic>>> fetchMyLargePartyBookings() async {
    try {
      final userId = currentUserId;
      if (userId == null) return [];

      // 1. Fetch normal large party request bookings
      final List<Map<String, dynamic>> bookingParties = [];
      final raw = await fetchBookings();
      if (raw != null) {
        bookingParties.addAll(
          raw
              .whereType<Map>()
              .where((b) => b['goingMode']?.toString() == 'party_request')
              .map((b) => Map<String, dynamic>.from(b)),
        );
      }

      // 2. Fetch group parties (<= 20 friends)
      final List<Map<String, dynamic>> groupParties = [];
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
                final totalCount = (gp['numberOfFriends'] ?? gp['totalParticipants'] ?? 5) is int
                    ? (gp['numberOfFriends'] ?? gp['totalParticipants'] ?? 5)
                    : (int.tryParse((gp['numberOfFriends'] ?? gp['totalParticipants'] ?? 5).toString()) ?? 5);
                final hostUser = gp['user'] ?? gp['host'];
                groupParties.add({
                  'id': gp['id'],
                  'bookingId': gp['id'],
                  'venue': gp['venue'],
                  'venueName': gp['venue']?['name'],
                  'venueAddress': gp['venue']?['addressLine1'] ?? gp['venue']?['city'] ?? '',
                  'status': gp['status']?.toString() ?? 'pending',
                  'bookingStatus': gp['status']?.toString() ?? 'pending',
                  'paymentStatus': gp['paymentStatus']?.toString(),
                  'adminApprovalStatus': gp['adminApprovalStatus']?.toString(),
                  'numberOfGuests': totalCount,
                  'numberOfFriends': totalCount,
                  'totalParticipants': totalCount,
                  'memberCount': totalCount > 1 ? totalCount - 1 : 1,
                  'hostCount': 1,
                  'partySubject': 'Group Party',
                  'bookingDate': gp['partyDate'],
                  'partyDate': gp['partyDate'],
                  'startTime': '08:00 PM',
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
          }
        }
      } catch (gpErr) {
        debugPrint('fetchMyGroupParties in fetchMyLargePartyBookings error: $gpErr');
      }

      // Combine both
      final List<Map<String, dynamic>> combined = [...bookingParties, ...groupParties];

      // Sort newest-first by createdAt
      combined.sort((a, b) {
        final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });

      return combined;
    } catch (e) {
      debugPrint('fetchMyLargePartyBookings error: $e');
      return [];
    }
  }

  /// Fetches ALL tickets for current user across standard bookings, group parties (<= 20), and confirmed party plans.
  static Future<List<Map<String, dynamic>>> fetchAllUserTickets() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final Map<String, Map<String, dynamic>> ticketMap = {};

    // 1. Fetch standard bookings
    try {
      final rawBookings = await fetchBookings();
      if (rawBookings != null) {
        for (final item in rawBookings) {
          if (item is Map) {
            final mapItem = Map<String, dynamic>.from(item);
            final key = mapItem['id']?.toString() ?? UniqueKey().toString();
            ticketMap[key] = mapItem;
          }
        }
      }
    } catch (e) {
      debugPrint('fetchAllUserTickets standard bookings error: $e');
    }

    // 2. Fetch group parties (<= 20 members as well as all sizes)
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
              final key = 'gp_${gp['id']}';
              ticketMap[key] = {
                'id': gp['id'],
                'bookingId': gp['id'],
                'ticketCode': gp['ticketCode'] ?? 'GP-${gp['id'].toString().substring(0, 8)}',
                'venue': gp['venue'],
                'venueName': gp['venue']?['name'] ?? 'Group Party Venue',
                'status': gp['status']?.toString().toLowerCase() ?? 'pending',
                'bookingStatus': gp['status']?.toString().toLowerCase() ?? 'pending',
                'numberOfGuests': gp['numberOfFriends'] ?? 1,
                'tablePackage': 'GROUP PARTY (${gp['numberOfFriends'] ?? 1} FRIENDS)',
                'bookingDate': gp['partyDate'],
                'startTime': gp['startTime'] ?? '08:00 PM',
                'totalAmount': gp['totalAmount'] ?? gp['tableBookingCharge'],
                'createdAt': gp['createdAt'],
                'mobileNumber': gp['mobileNumber'],
                'optionalMobileNumber': gp['optionalMobileNumber'],
                'foodPreference': gp['foodPreference'],
                'drinkPreference': gp['drinkPreference'],
                'isGroupParty': true,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('fetchAllUserTickets group parties error: $e');
    }

    // 3. Fetch user party plans (confirmed / matched)
    try {
      final myPlans = await fetchMyPartyPlans();
      for (final plan in myPlans) {
        final status = plan['status']?.toString().toLowerCase();
        if (status == 'confirmed' || status == 'active' || status == 'booked') {
          final key = 'plan_${plan['id']}';
          
          final rawDateTime = plan['planDateTime'] ?? plan['eventDateTime'] ?? plan['planDate'] ?? plan['partyDate'] ?? plan['bookingDate'] ?? plan['eventDate'] ?? plan['date'];
          String bDate = '';
          String sTime = plan['eventTime'] ?? plan['time'] ?? '08:00 PM';
          
          if (rawDateTime != null) {
            try {
              final dt = DateTime.parse(rawDateTime.toString()).toLocal();
              bDate = dt.toIso8601String().split('T')[0];
              sTime = DateFormat('hh:mm a').format(dt);
            } catch (_) {
              bDate = rawDateTime.toString().split('T')[0];
            }
          }

          ticketMap[key] = {
            'id': plan['id'],
            'bookingId': plan['id'],
            'ticketCode': plan['ticketCode'] ?? 'PP-${plan['id'].toString().substring(0, 8)}',
            'venue': plan['venue'],
            'venueName': plan['venue']?['name'] ?? plan['venueName'] ?? 'Party Venue',
            'status': status,
            'bookingStatus': status,
            'numberOfGuests': (plan['selectedUserIds'] is List ? (plan['selectedUserIds'] as List).length : 2),
            'tablePackage': 'PARTY PLAN MATCH',
            'bookingDate': bDate,
            'startTime': sTime,
            'totalAmount': plan['depositAmount'] ?? 198,
            'createdAt': plan['createdAt'],
            'isPartyPlan': true,
          };
        }
      }
    } catch (e) {
      debugPrint('fetchAllUserTickets party plans error: $e');
    }

    // 4. Fetch Strangers Meet Requests created by the user
    try {
      final myMeets = await fetchMyStrangersMeetRequests();
      for (final sm in myMeets) {
        final status = sm.status.toLowerCase();
        final payStatus = sm.paymentStatus.toLowerCase();
        if (payStatus == 'paid' || status == 'approved' || status == 'confirmed') {
          final key = 'sm_host_${sm.id}';
          ticketMap[key] = {
            'id': sm.id,
            'bookingId': sm.id,
            'ticketCode': sm.ticketId ?? 'SM-${sm.id.substring(0, 8)}',
            'venue': sm.venue,
            'venueName': sm.venue?['name'] ?? 'Stranger Meet Venue',
            'status': sm.status.toLowerCase(),
            'bookingStatus': sm.status.toLowerCase(),
            'numberOfGuests': sm.numberOfPersons,
            'tablePackage': 'STRANGER MEET HOST',
            'bookingDate': sm.eventDateTime.toIso8601String().split('T')[0],
            'startTime': DateFormat('hh:mm a').format(sm.eventDateTime),
            'totalAmount': sm.paymentAmount ?? 0.0,
            'createdAt': sm.createdAt?.toIso8601String(),
            'isStrangerMeet': true,
            'ticketUrl': sm.ticketUrl,
          };
        }
      }
    } catch (e) {
      debugPrint('fetchAllUserTickets strangers meets error: $e');
    }

    // 5. Fetch Strangers Meets joined by the user
    try {
      final joinedMeets = await fetchJoinedStrangersMeets();
      for (final sm in joinedMeets) {
        final userJoiner = sm.joiners?.firstWhere(
          (j) => j['userId'] == userId && (j['paymentStatus'] == 'paid' || j['status'] == 'paid' || j['status'] == 'accepted'),
          orElse: () => null,
        );
        if (userJoiner != null) {
          final key = 'sm_join_${sm.id}';
          ticketMap[key] = {
            'id': sm.id,
            'bookingId': sm.id,
            'ticketCode': sm.ticketId ?? 'SMJ-${sm.id.substring(0, 8)}',
            'venue': sm.venue,
            'venueName': sm.venue?['name'] ?? 'Stranger Meet Venue',
            'status': sm.status.toLowerCase(),
            'bookingStatus': sm.status.toLowerCase(),
            'numberOfGuests': 1,
            'tablePackage': 'STRANGER MEET GUEST',
            'bookingDate': sm.eventDateTime.toIso8601String().split('T')[0],
            'startTime': DateFormat('hh:mm a').format(sm.eventDateTime),
            'totalAmount': userJoiner['paymentAmount'] ?? sm.chargesPerHead,
            'createdAt': sm.createdAt?.toIso8601String(),
            'isStrangerMeet': true,
            'ticketUrl': sm.ticketUrl,
          };
        }
      }
    } catch (e) {
      debugPrint('fetchAllUserTickets joined strangers meets error: $e');
    }

    final List<Map<String, dynamic>> results = ticketMap.values.toList();
    results.sort((a, b) {
      final da = DateTime.tryParse(a['createdAt']?.toString() ?? a['bookingDate']?.toString() ?? '') ?? DateTime(0);
      final db = DateTime.tryParse(b['createdAt']?.toString() ?? b['bookingDate']?.toString() ?? '') ?? DateTime(0);
      return db.compareTo(da);
    });

    return results;
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

  static Future<List<Map<String, dynamic>>> fetchMyLikesAndMatches() async {
    try {
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

  static Future<List<Map<String, dynamic>>> fetchStrangersMeetFeed({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await get(
        '/api/mobile/strangers-meet/feed',
        queryParameters: {'page': page.toString(), 'limit': limit.toString()},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching strangers meet feed: $e');
      return [];
    }
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
  }) async {
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
          final myReqs = List<Map<String, dynamic>>.from(data['myRequests'] ?? []);
          for (final req in myReqs) {
            final pId = req['partyPlanId']?.toString() ?? req['planId']?.toString() ?? req['plan']?['id']?.toString();
            final reqStatus = (req['status'] ?? req['joinerPaymentStatus'] ?? 'pending').toString().toLowerCase();
            if (pId != null && pId.isNotEmpty && reqStatus != 'cancelled' && reqStatus != 'rejected') {
              markPartyPlanAsRequestedLocal(pId, req);
            }
          }
          return {
            'feed': List<Map<String, dynamic>>.from(data['data'] ?? []),
            'myRequests': myReqs,
            'incomingRequests': List<Map<String, dynamic>>.from(
              data['incomingRequests'] ?? [],
            ),
          };
        }
      }
      return {'feed': [], 'myRequests': [], 'incomingRequests': []};
    } catch (e) {
      debugPrint('Error fetching live feed: $e');
      return {'feed': [], 'myRequests': [], 'incomingRequests': []};
    }
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
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['message'] != null) {
          msg = data['message'].toString();
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
        );
      }

      return PartyPlanRequestResult(
        success: false,
        alreadyRequested: false,
        isNewRequest: false,
        message: msg,
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
            final pId = req['partyPlanId']?.toString() ?? req['planId']?.toString() ?? req['plan']?['id']?.toString();
            final reqStatus = (req['status'] ?? req['joinerPaymentStatus'] ?? 'pending').toString().toLowerCase();
            if (pId != null && pId.isNotEmpty && reqStatus != 'cancelled' && reqStatus != 'rejected') {
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

  static Future<Map<String, dynamic>?> acceptPartyPlanRequest(
    String reqId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/accept',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      }
    } catch (e) {
      debugPrint('acceptPartyPlanRequest error: $e');
    }
    return null;
  }

  /// Loads the authoritative Party Plan data used when opening a notification
  /// or push deep link, where the original payload only contains a plan ID.
  static Future<Map<String, dynamic>?> fetchPartyPlanDetail(String planId) async {
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
  static Future<bool> cancelPartyPlanRequest(String reqId, {String? reason}) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/cancel',
        body: {'userId': userId, 'reason': ?reason},
      );
      if (response.statusCode == 200) {
        String? targetPlanId;
        _cachedPartyPlanRequests.forEach((pId, req) {
          if (req['id']?.toString() == reqId) {
            targetPlanId = pId;
          }
        });
        if (targetPlanId != null) {
          markPartyPlanAsCancelledLocal(targetPlanId!);
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('cancelPartyPlanRequest error: $e');
      return false;
    }
  }

  /// Withdraws the caller's accepted request before their payment completes.
  static Future<bool> withdrawPartyPlanRequest(String reqId, {String? reason}) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/withdraw',
        body: {'userId': userId, 'reason': ?reason},
      );
      if (response.statusCode == 200) {
        String? targetPlanId;
        _cachedPartyPlanRequests.forEach((pId, req) {
          if (req['id']?.toString() == reqId) {
            targetPlanId = pId;
          }
        });
        if (targetPlanId != null) {
          markPartyPlanAsCancelledLocal(targetPlanId!);
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('withdrawPartyPlanRequest error: $e');
      return false;
    }
  }

  /// Host-only: withdraws an acceptance while the participant remains unpaid.
  static Future<bool> revokePartyPlanAcceptance(String reqId, {String? reason}) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/revoke',
        body: {'userId': userId, 'reason': ?reason},
      );
      return response.statusCode == 200;
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
        return true;
      }
    } catch (e) {
      debugPrint('verifyHostPayment error: $e');
    }
    return false;
  }

  static Future<bool> cancelPartyPlan(String planId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/cancel',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint('cancelPartyPlan error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> fetchWalletData() async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await get(
        '/api/mobile/wallet',
        queryParameters: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
    } catch (e) {
      debugPrint('fetchWalletData error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> createWalletRechargeOrder(double amount) async {
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

  static Future<Map<String, dynamic>?> payWithWallet({
    required double amount,
    String? planId,
    String? bookingId,
    String paymentType = 'booking_payment',
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/wallet/pay-with-wallet',
        body: {
          'userId': userId,
          'amount': amount,
          'planId': planId,
          'bookingId': bookingId,
          'paymentType': paymentType,
        },
      );
      if (response.body.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
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
          if (accountNumber != null && accountNumber.isNotEmpty) 'accountNumber': accountNumber,
          if (accountHolderName != null && accountHolderName.isNotEmpty) 'accountHolderName': accountHolderName,
          if (ifscCode != null && ifscCode.isNotEmpty) 'ifscCode': ifscCode,
          if (upiId != null && upiId.isNotEmpty) 'upiId': upiId,
          if (upiNumber != null && upiNumber.isNotEmpty) 'upiNumber': upiNumber,
          if (foodPreference != null && foodPreference.isNotEmpty) 'foodPreference': foodPreference,
          if (drinkPreference != null && drinkPreference.isNotEmpty) 'drinkPreference': drinkPreference,
        },
      );
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        try {
          final data = jsonDecode(response.body);
          final msg = data['message'] ?? data['error'] ?? 'Failed to submit request';
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
      final response = await get('/api/mobile/strangers-meet/$id');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return StrangersMeetRequest.fromJson(data['data']);
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
        final msg = data['message'] ?? data['error'] ?? 'Failed to initiate payment';
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
        return data['data'];
      } else {
        final msg = data['message'] ?? data['error'] ?? 'Failed to confirm payment';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('payStrangersMeetRequest error: $e');
      rethrow;
    }
  }

  static Future<bool> updateStrangersMeetCharges(String id, double chargesPerHead) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await patch(
        '/api/mobile/strangers-meet/$id/charges',
        body: {
          'userId': userId,
          'chargesPerHead': chargesPerHead,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
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
        final msg = data['message'] ?? data['error'] ?? 'Failed to initiate join payment';
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
        return data['data'];
      } else {
        final msg = data['message'] ?? data['error'] ?? 'Failed to confirm join payment';
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
        return true;
      } else {
        final msg = data['message'] ?? data['error'] ?? 'Failed to complete strangers meet';
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
          if (foodPreference != null && foodPreference.isNotEmpty) 'foodPreference': foodPreference,
          if (drinkPreference != null && drinkPreference.isNotEmpty) 'drinkPreference': drinkPreference,
        },
      );
      final data = jsonDecode(response.body);
      if ((response.statusCode == 201 || response.statusCode == 200) && data['success'] == true) {
        return true;
      } else {
        final msg = data['message'] ?? data['error'] ?? 'Failed to send join request';
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
        return true;
      } else {
        final msg = data['message'] ?? data['error'] ?? 'Failed to handle join request';
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
        return true;
      } else {
        final msg = data['message'] ?? data['error'] ?? 'Failed to submit settlement request';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('submitStrangersMeetSettlement error: $e');
      rethrow;
    }
  }

  /// Fetch financial breakdown for a Strangers Meet (platform fee, host profit, settlement)
  static Future<Map<String, dynamic>?> fetchStrangersMeetFinancials(String id) async {
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

  static Future<http.Response> get(
    String endpoint, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$endpoint',
    ).replace(queryParameters: queryParameters);
    debugPrint('GET $uri');
    final headers = {
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };

    http.Response response;
    if (body != null) {
      final request = http.Request('GET', uri);
      request.headers.addAll(headers);
      request.body = jsonEncode(body);
      final streamedResponse = await request.send();
      response = await http.Response.fromStream(streamedResponse);
    } else {
      response = await http.get(uri, headers: headers);
    }

    _checkAutoblockedResponse(response);
    return response;
  }

  static Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await put('/api/profile/update', body: data);
      //debugPrint('updateProfile ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        return resData['success'] == true;
      }
    } catch (e) {
      debugPrint('updateProfile error: $e');
    }
    return false;
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
      final fields = <String, String>{
        'isPrimary': isPrimary.toString(),
      };
      final response = await postMultipart('/api/profile/photos', files: files, fields: fields);
      debugPrint('uploadProfilePhotos status: ${response.statusCode}');
      debugPrint('uploadProfilePhotos body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (e) {
      debugPrint('uploadProfilePhotos error: $e');
    }
    return false;
  }

  static Future<bool> deleteProfilePhoto(String photoId) async {
    try {
      final response = await delete('/api/profile/photos/$photoId');
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        return true;
      }
    } catch (e) {
      debugPrint('deleteProfilePhoto error: $e');
    }
    return false;
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
        return {
          'success': false,
          'message': msg,
        };
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
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('PUT $uri');
    final headers = {
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final response = await http.put(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkAutoblockedResponse(response);
    return response;
  }

  static Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('POST $uri');
    final headers = {
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkAutoblockedResponse(response);
    return response;
  }

  static Future<http.Response> patch(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('PATCH $uri');
    final headers = {
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final response = await http.patch(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkAutoblockedResponse(response);
    return response;
  }

  static Future<http.Response> delete(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    debugPrint('DELETE $uri');
    final headers = {
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final request = http.Request('DELETE', uri);
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkAutoblockedResponse(response);
    return response;
  }

  // â”€â”€â”€ Chat Module â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Step 2 â€” GET /api/mobile/chat/conversations?userId=
  static Future<List<Map<String, dynamic>>> fetchConversations(
    String userId,
  ) async {
    try {
      final response = await get(
        '/api/mobile/chat/conversations',
        queryParameters: {'userId': userId},
      );
      // debugPrint('fetchConversations ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchConversations error: $e');
    }
    return [];
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
      debugPrint('[Chat] createOrGetConversation status=${response.statusCode}');
      debugPrint('[Chat] createOrGetConversation body=${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final convId = data['data']?['conversationId']?.toString() ??
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
      debugPrint('[Chat] fetchMessages status=${response.statusCode} convId=$conversationId');
      debugPrint('[Chat] fetchMessages body=${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
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

  /// Step 5A-5E â€” POST /api/mobile/chat/conversations/:id/messages
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

      final response = await post(
        '/api/mobile/chat/conversations/$conversationId/messages',
        body: body,
      );
      debugPrint('[Chat] sendMessage status=${response.statusCode} convId=$conversationId');
      debugPrint('[Chat] sendMessage body=${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
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

  /// Step 8 â€” DELETE .../conversations/:id/messages/:messageId
  static Future<bool> deleteMessage(
    String conversationId,
    String messageId,
    String userId,
  ) async {
    try {
      final response = await delete(
        '/api/mobile/chat/conversations/$conversationId/messages/$messageId',
        body: {'userId': userId},
      );
      // debugPrint('deleteMessage ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('deleteMessage error: $e');
    }
    return false;
  }

  // â”€â”€â”€ Push Notification Token â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  static bool get isLoggedIn => _authToken != null && _authToken!.trim().isNotEmpty;

  static String? get currentUserId {
    if (_authToken != null && _authToken!.trim().isNotEmpty) {
      try {
        final parts = _authToken!.split('.');
        if (parts.length == 3) {
          String normalized = parts[1].replaceAll('-', '+').replaceAll('_', '/');
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
          final rawId = data['userId']?.toString() ??
              data['id']?.toString() ??
              data['_id']?.toString() ??
              data['user_id']?.toString() ??
              data['sub']?.toString();
          if (rawId != null && rawId != 'undefined' && rawId != 'null' && rawId.trim().isNotEmpty) {
            return rawId;
          }
        }
      } catch (e) {
        debugPrint('Error decoding JWT in currentUserId: $e');
      }
    }
    if (cachedCurrentUser?.id != null && cachedCurrentUser!.id.trim().isNotEmpty) {
      return cachedCurrentUser!.id;
    }
    return null;
  }

  // â”€â”€â”€ Notifications & Local Persistent Read State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static final Set<String> localReadRequestIds = {};
  static final Set<String> localReadNotificationIds = {};
  static bool _readIdsLoaded = false;

  static Future<void> loadLocalReadIds() async {
    _ensureLocalStateForCurrentUser();
    if (_readIdsLoaded) return;
    try {
      final userId = currentUserId;
      if (userId == null || userId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final reqs = prefs.getStringList(
            _userPreferenceKey('localReadRequestIds', userId),
          ) ??
          [];
      final notifs = prefs.getStringList(
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

  /// Fetch in-app notifications for current user
  static Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final userId = currentUserId;
    if (userId == null) return [];
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
        if (list is List) return List<Map<String, dynamic>>.from(list);
      }
    } catch (e) {
      debugPrint('fetchNotifications error: $e');
    }
    return [];
  }

  static Future<Map<String, int>> fetchBadgeCounts() async {
    final userId = currentUserId;
    if (userId == null) {
      return {'liveFeedCount': 0, 'chatCount': 0, 'totalCount': 0};
    }
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
          return {
            'liveFeedCount': data['data']['liveFeedCount'] ?? 0,
            'chatCount': data['data']['chatCount'] ?? 0,
            'totalCount': data['data']['totalCount'] ?? 0,
          };
        }
      }
    } catch (e) {
      debugPrint('fetchBadgeCounts error: $e');
    }
    return {'liveFeedCount': 0, 'chatCount': 0, 'totalCount': 0};
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

  /// Clear all notifications (mark as cleared persistently)
  static Future<bool> clearAllNotifications() async {
    final userId = currentUserId;
    if (userId == null) return false;
    await loadLocalReadIds();
    // Only clear notification IDs here.
    // localReadRequestIds is managed separately by markAllNotificationsAsRead
    // in live_feed_screen so feed items can be re-added as "read" after this call.
    localReadNotificationIds.clear();
    await saveLocalReadNotificationIds();
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
  static Future<bool> rejectPartyPlanRequest(String reqId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/reject',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) return true;
    } catch (e) {
      debugPrint('rejectPartyPlanRequest error: $e');
    }
    return false;
  }

  /// Accept a party plan invite
  static Future<Map<String, dynamic>?> acceptPartyPlanInvite(String reqId) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/accept-invite',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data;
      }
    } catch (e) {
      debugPrint('acceptPartyPlanInvite error: $e');
    }
    return null;
  }

  /// Joiner proceeds to pay after host accepts
  static Future<Map<String, dynamic>?> initiateJoinerPayment(
    String reqId,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;
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

    final streamedResponse = await request.send();
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

  static Future<Map<String, dynamic>?> initiateLargePartyPayment(String bookingId) async {
    try {
      final response = await post(
        '/api/mobile/bookings/$bookingId/initiate-large-party-payment',
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      } else {
        debugPrint('initiateLargePartyPayment error [${response.statusCode}]: ${response.body}');
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
      final response = await post(
        '/api/mobile/bookings/$bookingId/verify-large-party-payment',
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

  static Future<Map<String, dynamic>?> payNowBooking(String bookingId) async {
    final userId = currentUserId;
    try {
      final response = await post(
        '/api/mobile/bookings/$bookingId/pay-now',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
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
        return data['success'] == true;
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
        body: {
          'userId': userId,
          'venueId': venueId,
          'eventDate': date,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
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

  static Future<Map<String, dynamic>?> fetchPartnerProfilePreview(String targetUserId) async {
    try {
      final response = await get('/api/mobile/nights/partners/$targetUserId/profile');
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
        },
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['success'] == true ? Map<String, dynamic>.from(data) : null;
      }
    } catch (e) {
      debugPrint('sendNightPartnerRequest error: $e');
    }
    return null;
  }

  static Future<bool> respondToNightPartnerRequest({
    required String requestId,
    required String action, // 'accept' | 'decline'
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await patch(
        '/api/mobile/nights/requests/$requestId',
        body: {
          'partnerId': userId,
          'action': action,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('respondToNightPartnerRequest error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> initiateMatchPayment(String matchId) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/nights/matches/$matchId/pay',
        body: {'hostId': userId},
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
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final response = await post(
        '/api/mobile/nights/matches/$matchId/verify',
        body: {
          'razorpay_order_id': razorpayOrderId,
          'razorpay_payment_id': razorpayPaymentId,
          'razorpay_signature': razorpaySignature,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('verifyMatchPayment error: $e');
    }
    return null;
  }


  // â”€â”€ Swipe Status & Subscription Limits â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns the current user's swipe action on [targetUserId] today,
  /// and the plan limits so the UI can enforce them without a server round-trip.
  /// Response: { alreadyLiked, alreadySuperLiked, dailyLikesLimit, dailyLikesUsed,
  ///             superlikesRemaining, superlikesPerCycle }
  static Future<Map<String, dynamic>> fetchSwipeStatus(String targetUserId) async {
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

  static Future<Map<String, dynamic>?> backtrackSwipe(String targetUserId) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/user/backtrack',
        body: {
          'userId': userId,
          'targetUserId': targetUserId,
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data'] ?? data);
        }
      } else if (response.statusCode == 403) {
        final data = jsonDecode(response.body);
        return {'limitReached': true, 'message': data['message']};
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
      final response = await get(
        '/api/mobile/subscriptions/current',
      );
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



  static Future<Map<String, dynamic>?> createGroupParty({
    required String venueId,
    required int numberOfFriends,
    required String partyDate,
    required String mobileNumber,
    String? optionalMobileNumber,
    String? foodPreference,
    String? drinkPreference,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await post(
        '/api/mobile/group-parties',
        body: {
          'userId': userId,
          'venueId': venueId,
          'numberOfFriends': numberOfFriends,
          'partyDate': partyDate,
          'mobileNumber': mobileNumber.trim(),
          if (optionalMobileNumber != null && optionalMobileNumber.trim().isNotEmpty)
            'optionalMobileNumber': optionalMobileNumber.trim(),
          if (foodPreference != null && foodPreference.trim().isNotEmpty)
            'foodPreference': foodPreference.trim(),
          if (drinkPreference != null && drinkPreference.trim().isNotEmpty)
            'drinkPreference': drinkPreference.trim(),
        },
      );
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
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
  }) async {
    try {
      final response = await post(
        '/api/mobile/group-parties/verify',
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
      debugPrint('verifyGroupPartyPayment error: $e');
    }
    return false;
  }

  // â”€â”€ Subscription API Methods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<List<dynamic>> fetchSubscriptionPackages() async {
    try {
      final response = await get('/api/mobile/subscriptions/packages');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return List<dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchSubscriptionPackages error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createSubscriptionOrder(String packageId) async {
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
        'success': response.statusCode == 200 || response.statusCode == 201 ? (data['success'] ?? true) : false,
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
        'success': response.statusCode == 200 || response.statusCode == 201 ? (data['success'] ?? true) : false,
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

  static Future<Map<String, dynamic>?> useBoost() async {
    try {
      final response = await post('/api/mobile/subscriptions/use-boost');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('useBoost error: $e');
    }
    return null;
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
  static Future<Map<String, dynamic>?> fetchPartyPlanTicket(String reqId) async {
    try {
      final response = await get('/api/mobile/party-plans/requests/$reqId/ticket');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
      debugPrint('fetchPartyPlanTicket failed [${response.statusCode}]: ${response.body}');
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
      final Uint8List profileBytes = await XFile(profilePhotoPath).readAsBytes();

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
        body: {
          'selfie': selfieBase64,
          'profilePhoto': profileBase64,
        },
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
      return {'success': false, 'message': 'Authentication required. Please log in again.'};
    }

    try {
      final response = await post(
        '/api/mobile/user/delete-account',
        body: {
          'userId': userId,
          'password': password,
          'reason': reason ?? '',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await logout();
        return {'success': true, 'message': data['message'] ?? 'Account deleted successfully'};
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
    final headers = {'Content-Type': 'application/json'};
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  static Future<http.Response> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    return await http.get(uri, headers: _authHeaders);
  }

  static Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    return await http.post(uri, headers: _authHeaders, body: jsonEncode(body));
  }

  /// Fetch user tickets with tab filtering ('upcoming', 'active', 'used', 'expired', 'cancelled')
  static Future<List<Map<String, dynamic>>> getUserTickets({String tab = 'all'}) async {
    final userId = currentUserId ?? '';
    if (userId.isEmpty) return [];
    try {
      final response = await _get('/api/mobile/tickets?userId=$userId&tab=$tab');
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
  static Future<Map<String, dynamic>> getTicketDownloadUrl(String ticketId) async {
    final userId = currentUserId ?? '';
    try {
      final response = await _get('/api/mobile/tickets/$ticketId/download-url?userId=$userId');
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
  static Future<Map<String, dynamic>> createTicketShareToken(String ticketId) async {
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

  /// Fetch pending/unanswered safety check for current user
  static Future<Map<String, dynamic>?> fetchPendingSafetyCheck() async {
    try {
      final userId = currentUserId;
      if (userId == null) return null;
      final response = await _get('/api/mobile/party-plans/safety-checks/pending?userId=$userId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchPendingSafetyCheck error: $e');
    }
    return null;
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
      final body = <String, dynamic>{
        'userId': userId,
        'reason': reason,
      };
      if (otherReasonText != null && otherReasonText.isNotEmpty) {
        body['otherReasonText'] = otherReasonText;
      }
      final response = await _post(
        // Mutual cancellation belongs to the Party Plan controller mounted at
        // /api/mobile/plans (not the request-management route namespace).
        '/api/mobile/plans/$planId/cancellation-request',
        body,
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('requestPartyPlanCancellation error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Fetch the active cancellation request state for a Party Plan
  static Future<Map<String, dynamic>?> getPartyPlanCancellationRequest(String planId) async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final response = await _get('/api/mobile/plans/$planId/cancellation-request?userId=$userId');
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
  static Future<Map<String, dynamic>> respondToPartyPlanCancellationRequest({
    required String planId,
    required String requestId,
    required String action,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }
    try {
      final response = await _post(
        '/api/mobile/plans/$planId/cancellation-request/respond',
        {
          'userId': userId,
          'requestId': requestId,
          'action': action,
        },
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('respondToPartyPlanCancellationRequest error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> confirmArrival({
    required String planId,
    required String userId,
    required bool hasArrived,
  }) async {
    try {
      final response = await _post(
        '/api/mobile/party-plans/$planId/confirm-arrival',
        {'userId': userId, 'hasArrived': hasArrived},
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('confirmArrival error: $e');
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
      final response = await _post(
        '/api/mobile/party-plans/$planId/review',
        {
          'reviewerId': reviewerId,
          'rating': rating,
          'comment': comment,
          'isReported': isReported,
          'reportReason': reportReason,
        },
      );
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

  PartyPlanRequestResult({
    required this.success,
    required this.alreadyRequested,
    required this.isNewRequest,
    required this.message,
    this.requestId,
    this.status,
  });
}
