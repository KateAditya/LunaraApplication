import 'dart:io' show Platform;
import 'dart:convert';
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
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'notification_navigator.dart';
import '../screens/auth/autoblocked_warning_screen.dart';

class ApiService {
  // Toggle this to true to use your local backend, false for production
  static const bool isLocal = false;

  // Uses your machine's local IP (192.168.0.169) for local dev on a real device
  static String get baseUrl {
    if (!isLocal) return 'https://lunara-api-server-a8gfdvg0hjdec6gx.centralindia-01.azurewebsites.net';
    if (kIsWeb) {
      return 'http://localhost:9076';
    }
    return 'http://192.168.0.169:9076';
  }

  static String? _authToken;
  static String? selectedCity;
  static User? cachedCurrentUser;

  static Future<void> initAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('auth_token');
    selectedCity = prefs.getString('selected_city');
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

    if (socket != null && socket!.connected) {
      socket!.disconnect();
    }

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
      socket = null;
    }
  }

  static Future<void> setAuthToken(String? token) async {
    _authToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString('auth_token', token);
      initSocket();
    } else {
      await prefs.remove('auth_token');
      disconnectSocket();
    }
  }

  static Future<void> clearAuthToken() async {
    _authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    disconnectSocket();
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
    await clearAuthToken();
  }

  static Future<void> setSelectedCity(String city) async {
    selectedCity = city;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_city', city);
  }

  static Future<User?> fetchProfile({String? userId}) async {
    try {
      final targetUserId = userId ?? currentUserId;
      if (targetUserId == null) {
        debugPrint('Error fetching profile: targetUserId is null');
        return null;
      }

      //debugPrint('Fetching profile for userId: $targetUserId');

      // Use query parameter only, as Flutter Web (fetch) does not allow bodies in GET requests
      final response = await get(
        '/api/mobile/user/userprofile',
        queryParameters: {'userId': targetUserId},
      );

      //debugPrint('Profile Response Status: ${response.statusCode}');
      //debugPrint('Profile Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final user = User.fromJson(data);
          if (userId == null || userId == currentUserId) {
            cachedCurrentUser = user;
          }
          return user;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
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

  static Future<List<Map<String, dynamic>>> fetchCustomers() async {
    try {
      final response = await get('/api/mobile/user/customers');
      //debugPrint('Customers Response Status: ${response.statusCode}');
      //debugPrint('Customers Response Body: ${response.body}');

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
      final response = await get(
        '/api/mobile/party-plans',
        queryParameters: {
          'status': status,
          'page': page.toString(),
          'limit': limit.toString(),
        },
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
      }
    } catch (e) {
      debugPrint('submitLargePartyRequest error: $e');
    }
    return false;
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
  // ─── City APIs ──────────────────────────────────────────────────────────────

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
          return {
            'feed': List<Map<String, dynamic>>.from(data['data'] ?? []),
            'myRequests': List<Map<String, dynamic>>.from(
              data['myRequests'] ?? [],
            ),
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

  // ─── Party Plan Request APIs ────────────────────────────────────────────────

  static Future<bool> requestToJoinPartyPlan(String planId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/requests',
        body: {'userId': userId},
      );
      if (response.statusCode == 201) {
        return true;
      }
    } catch (e) {
      debugPrint('requestToJoinPartyPlan error: $e');
    }
    return false;
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
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('fetchMyPartyPlanRequests error: $e');
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

  static Future<bool> verifyJoinerPayment(
    String reqId,
    String orderId,
    String paymentId,
    String signature,
  ) async {
    try {
      final response = await post(
        '/api/mobile/party-plans/requests/$reqId/joiner-pay',
        body: {
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
    try {
      final response = await post(
        '/api/mobile/party-plans/$planId/host-pay',
        body: {
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

  // ─── Strangers Meet APIs ───────────────────────────────────────────────────

  static Future<bool> submitStrangersMeetRequest({
    required String venueId,
    required String subject,
    required String tagline,
    required String eventDateTime,
    required int numberOfPersons,
    required double chargesPerHead,
    required String mobileNumber,
    String? alternateMobileNumber,
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
        },
      );
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('submitStrangersMeetRequest error: $e');
    }
    return false;
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
    if (userId == null) return null;

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/initiate-payment',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('initiateStrangersMeetPayment error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> payStrangersMeetRequest(
    String id,
    String razorpayOrderId,
    String paymentId,
    String signature,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;

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
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
    } catch (e) {
      debugPrint('payStrangersMeetRequest error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> initiateStrangersMeetJoinPayment(
    String id,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/join/initiate-payment',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('initiateStrangersMeetJoinPayment error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> payStrangersMeetJoin(
    String id,
    String razorpayOrderId,
    String paymentId,
    String signature,
  ) async {
    final userId = currentUserId;
    if (userId == null) return null;

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
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
    } catch (e) {
      debugPrint('payStrangersMeetJoin error: $e');
    }
    return null;
  }

  static Future<bool> completeStrangersMeet(String id) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await patch(
        '/api/mobile/strangers-meet/$id/complete',
        body: {'userId': userId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('completeStrangersMeet error: $e');
    }
    return false;
  }

  static Future<bool> sendStrangersMeetJoinRequest(String id) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/join-request',
        body: {'userId': userId},
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('sendStrangersMeetJoinRequest error: $e');
    }
    return false;
  }

  static Future<bool> handleStrangersMeetJoinRequest(
    String id,
    String joinerId,
    String action,
  ) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await patch(
        '/api/mobile/strangers-meet/$id/join-request/$joinerId',
        body: {'userId': userId, 'action': action},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('handleStrangersMeetJoinRequest error: $e');
    }
    return false;
  }

  static Future<bool> submitStrangersMeetSettlement(
    String id,
    String bankDetails,
  ) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final response = await post(
        '/api/mobile/strangers-meet/$id/settlement-request',
        body: {'userId': userId, 'bankDetails': bankDetails},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('submitStrangersMeetSettlement error: $e');
    }
    return false;
  }

  // ───────────────────────────────────────────────────────────────────────────

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
    List<String> fileNames,
  ) async {
    try {
      debugPrint(
        'uploadProfilePhotos: preparing to send ${fileBytes.length} files',
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
      final response = await postMultipart('/api/profile/photos', files: files);
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

  static Future<bool> changePassword(
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
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Just return true if status is 200/201
        return true;
      }
    } catch (e) {
      debugPrint('changePassword error: $e');
    }
    return false;
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

  // ─── Chat Module ───────────────────────────────────────────────────────────

  /// Step 2 — GET /api/mobile/chat/conversations?userId=
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

  /// Step 1 — GET /api/mobile/chat/icebreakers
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

  /// Step 3 — POST /api/mobile/chat/conversations
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
      // debugPrint('createOrGetConversation ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']?['conversationId']?.toString() ??
              data['data']?['id']?.toString();
        }
      }
    } catch (e) {
      debugPrint('createOrGetConversation error: $e');
    }
    return null;
  }

  /// Step 4 — GET /api/mobile/chat/conversations/:id/messages
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
        'before': ?before,
      };
      final response = await get(
        '/api/mobile/chat/conversations/$conversationId/messages',
        queryParameters: params,
      );
      // debugPrint('fetchMessages ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
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

      final response = await post(
        '/api/mobile/chat/conversations/$conversationId/messages',
        body: body,
      );
      //debugPrint('sendMessage ${response.statusCode}: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('sendMessage error: $e');
    }
    return null;
  }

  /// Step 6A/6B — PATCH .../messages/:messageId/invitation
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

  /// Step 7 — PATCH .../conversations/:id/read
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

  /// Step 8 — DELETE .../conversations/:id/messages/:messageId
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

  // ─── Push Notification Token ───────────────────────────────────────────────

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

  static String? get currentUserId {
    if (_authToken == null) return null;
    try {
      final parts = _authToken!.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final data = jsonDecode(payload);
      // debugPrint('Decoded JWT payload: $data');
      return data['id']?.toString() ??
          data['userId']?.toString() ??
          data['_id']?.toString();
    } catch (e) {
      debugPrint('Error decoding JWT: $e');
      return null;
    }
  }

  // ─── Notifications ──────────────────────────────────────────────────────────

  /// Fetch in-app notifications for current user
  static Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      final response = await get(
        '/api/mobile/user/notifications',
        queryParameters: {'userId': userId},
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
    try {
      final response = await get(
        '/api/mobile/user/badge-counts',
        queryParameters: {'userId': userId},
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
    try {
      await patch('/api/mobile/user/notifications/$notificationId/read');
    } catch (e) {
      debugPrint('markNotificationRead error: $e');
    }
  }

  /// Clear all notifications (mark as cleared persistently)
  static Future<bool> clearAllNotifications() async {
    final userId = currentUserId;
    if (userId == null) return false;
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
    try {
      await patch('/api/mobile/user/requests/$reqId/read');
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

  // ── Chat Subscription APIs ──────────────────────────────────────────────────

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
      debugPrint('updateAdminChatSettings error: \$e');
    }
    return false;
  }
}
