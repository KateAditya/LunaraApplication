import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme.dart';
import 'package:lunara_app/screens/profile/profile_screen.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../services/realtime_sync_manager.dart';
import '../discovery/venue_detail_screen.dart';
import '../../models/strangers_meet_request.dart';
import '../../models/venue.dart';
import '../../widgets/lunara_network_image.dart';
import 'strangers_meet_payment_screen.dart';
import 'strangers_meet_ticket_screen.dart';
import 'chat_screen.dart';
import 'party_plan_detail_screen.dart';
import '../../services/optimistic_action_guard.dart';
import '../../widgets/dialogs/time_lock_blocked_dialog.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic>? venue;

  const PostDetailScreen({super.key, required this.post, this.venue});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  bool _isLoading = true;
  StrangersMeetRequest? _meetRequest;
  bool _isProcessing = false;
  bool _alreadyRequested = false;
  bool _isPartyPlanStatusLoading = true;
  bool _isInvitedUser = false;
  String? _partyPlanRequestStatus;
  String? _partyPlanActiveRequestId;
  bool _isAcceptingInvite = false;
  bool _isDecliningInvite = false;
  late Razorpay _razorpay;
  String? _lastOrderId;
  double? _calculatedDistanceKm;
  bool _isFetchingDistance = false;
  final Map<String, String> _optimisticJoinerStatus = {};
  final Set<String> _loadingJoinerActions = {};

  @override
  void initState() {
    super.initState();
    _checkAndFetchDistanceSilently();
    if (!kIsWeb) {
      try {
        _razorpay = Razorpay();
        _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
        _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
        _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      } catch (e) {
        debugPrint('Razorpay init error: $e');
      }
    }

    final targetPlanId = widget.post['id']?.toString() ?? '';
    final currentUserId = ApiService.currentUserId ?? '';
    final hostId = (widget.post['userId'] ?? widget.post['hostId'] ?? widget.post['user']?['id'] ?? '').toString();
    final selectedUsers = widget.post['selectedUsers'] ?? widget.post['selectedUserIds'];
    final bool inSelectedUsers = selectedUsers is List && selectedUsers.any((u) => u?.toString() == currentUserId);

    if (widget.post['isInvite'] == true ||
        widget.post['isInvitedUser'] == true ||
        widget.post['type'] == 'party_plan_invitation' ||
        widget.post['requestType'] == 'private_invite' ||
        (currentUserId.isNotEmpty && currentUserId != hostId && inSelectedUsers)) {
      _isInvitedUser = true;
    }

    _alreadyRequested = widget.post['hasRequested'] == true ||
        widget.post['isRequested'] == true ||
        widget.post['requestStatus'] == 'pending' ||
        widget.post['myRequest'] != null ||
        _isInvitedUser ||
        ApiService.isPartyPlanRequestedSync(targetPlanId);

    RealtimeSyncManager.instance.strangerMeetNotifier.addListener(_onRealtimePostDetailChanged);
    RealtimeSyncManager.instance.globalSyncTick.addListener(_onRealtimePostDetailChanged);

    if (widget.post['type'] == 'strangers_meet') {
      _loadStrangersMeetDetails();
      ApiService.addSocketListener(
        'strangers_meet_updated',
        _onStrangersMeetUpdated,
      );
    } else {
      _isLoading = false;
      _loadPartyPlanDetails();
    }
  }

  void _onRealtimePostDetailChanged() {
    if (!mounted) return;
    if (widget.post['type'] == 'strangers_meet') {
      _loadStrangersMeetDetails(showFullScreenLoader: false);
    } else {
      _loadPartyPlanDetails();
    }
  }

  Future<void> _loadPartyPlanDetails() async {
    try {
      final targetPlanId = widget.post['id']?.toString() ?? '';
      if (targetPlanId.isEmpty) {
        if (mounted) {
          setState(() {
            _isPartyPlanStatusLoading = false;
          });
        }
        return;
      }
      final currentUserId = ApiService.currentUserId ?? '';

      final results = await Future.wait([
        ApiService.fetchPartyPlanDetail(targetPlanId),
        ApiService.fetchMyPartyPlanRequests(),
      ]);

      final planDetail = results[0] as Map<String, dynamic>?;
      final myRequests = results[1] as List<Map<String, dynamic>>? ?? [];

      bool requested = false;
      bool isInvited = false;
      String? reqStatus;
      String? reqId;

      final planData = planDetail ?? widget.post;
      final hostId = (planData['userId'] ?? planData['hostId'] ?? planData['user']?['id'] ?? widget.post['userId'] ?? '').toString();
      final bool isHost = currentUserId.isNotEmpty && currentUserId == hostId;

      final selectedUsers = planData['selectedUsers'] ?? planData['selectedUserIds'] ?? widget.post['selectedUsers'] ?? widget.post['selectedUserIds'];
      final bool inSelectedUsers = selectedUsers is List && selectedUsers.any((u) => u?.toString() == currentUserId);

      if (currentUserId.isNotEmpty && !isHost && (inSelectedUsers || planData['isInvite'] == true || planData['requestType'] == 'private_invite' || widget.post['isInvite'] == true)) {
        isInvited = true;
      }

      if (planData['requests'] is List) {
        for (final r in planData['requests']) {
          if (r is Map) {
            final requesterId = (r['requesterId'] ?? r['requester']?['id'] ?? r['userId'] ?? '').toString();
            if (currentUserId.isNotEmpty && requesterId == currentUserId) {
              reqId = r['id']?.toString();
              reqStatus = (r['status'] ?? 'pending').toString().toLowerCase();
              final reqIsInvite = r['isInvite'] == true || r['requestType'] == 'private_invite' || inSelectedUsers;
              if (reqIsInvite) isInvited = true;
              if (reqStatus != 'cancelled' && reqStatus != 'rejected' && reqStatus != 'declined') {
                requested = true;
              }
              break;
            }
          }
        }
      }

      for (final req in myRequests) {
        final planId = req['partyPlanId']?.toString() ?? req['planId']?.toString() ?? req['plan']?['id']?.toString();
        if (planId == targetPlanId) {
          reqId = req['id']?.toString() ?? reqId;
          final rawStatus = (req['status'] ?? req['joinerPaymentStatus'] ?? 'pending').toString().toLowerCase();
          reqStatus = rawStatus;
          bool isPaymentExpired = false;
          final paymentTimeoutAtStr = req['paymentTimeoutAt'] ?? req['paymentDeadlineAt'];
          if (paymentTimeoutAtStr != null) {
            try {
              final timeout = DateTime.parse(paymentTimeoutAtStr.toString()).toUtc();
              if (timeout.isBefore(DateTime.now().toUtc())) {
                isPaymentExpired = true;
              }
            } catch (_) {}
          }
          final reqIsInvite = req['isInvite'] == true ||
              req['requestType'] == 'private_invite' ||
              req['isPrivateInvite'] == true ||
              req['invitedBy'] != null ||
              inSelectedUsers;
          if (reqIsInvite) {
            isInvited = true;
          }

          if (rawStatus != 'cancelled' &&
              rawStatus != 'rejected' &&
              rawStatus != 'declined' &&
              rawStatus != 'payment_failed' &&
              !isPaymentExpired) {
            requested = true;
          } else {
            ApiService.markPartyPlanAsCancelledLocal(targetPlanId);
            requested = false;
          }
          break;
        }
      }

      if (isInvited && reqId == null) {
        reqId = targetPlanId;
      }

      if (mounted) {
        setState(() {
          _alreadyRequested = requested || isInvited;
          _isInvitedUser = isInvited;
          _partyPlanRequestStatus = reqStatus ?? (_isInvitedUser ? 'pending' : null);
          _partyPlanActiveRequestId = reqId;
          _isPartyPlanStatusLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading party plan details in PostDetailScreen: $e');
      if (mounted) {
        setState(() {
          _isPartyPlanStatusLoading = false;
        });
      }
    }
  }

  Future<void> _handleAcceptPartyPlanInvite() async {
    final reqId = _partyPlanActiveRequestId ?? widget.post['id']?.toString() ?? '';
    if (reqId.isEmpty) return;

    setState(() => _isAcceptingInvite = true);
    try {
      final res = await ApiService.acceptPartyPlanInvite(reqId);
      if (!mounted) return;
      setState(() => _isAcceptingInvite = false);

      if (res != null && res['success'] == true) {
        final bool isSelfPay = res['isSelfPay'] == true || (res['message']?.toString().toLowerCase().contains('host') ?? false);
        final bool hostPaid = res['hostPaid'] == true;
        setState(() {
          _partyPlanRequestStatus = isSelfPay ? (hostPaid ? 'confirmed' : 'accepted') : 'payment_pending';
          _alreadyRequested = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? '🎉 Invite Accepted!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadPartyPlanDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Failed to accept invite'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAcceptingInvite = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting invite: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleRejectPartyPlanInvite() async {
    final reqId = _partyPlanActiveRequestId ?? widget.post['id']?.toString() ?? '';
    if (reqId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F003A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Decline Invitation?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to decline this party plan invitation?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Decline', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isDecliningInvite = true);
    try {
      final success = await ApiService.rejectPartyPlanRequest(reqId);
      if (!mounted) return;
      setState(() => _isDecliningInvite = false);

      if (success) {
        final targetPlanId = widget.post['id']?.toString() ?? '';
        if (targetPlanId.isNotEmpty) {
          ApiService.markPartyPlanAsCancelledLocal(targetPlanId);
        }
        setState(() {
          _alreadyRequested = false;
          _isInvitedUser = false;
          _partyPlanRequestStatus = 'declined';
          _partyPlanActiveRequestId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitation declined.'),
            backgroundColor: Colors.grey,
          ),
        );
        _loadPartyPlanDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline invitation.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDecliningInvite = false);
        debugPrint('Error declining invite: $e');
      }
    }
  }

  Future<void> _checkAndFetchDistanceSilently() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          _fetchActualDistance(showPermissionPrompt: false);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchActualDistance({bool showPermissionPrompt = true}) async {
    if (_isFetchingDistance) return;
    setState(() => _isFetchingDistance = true);

    try {
      if (showPermissionPrompt) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          await Geolocator.openLocationSettings();
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      }

      LocationPermission finalPerm = await Geolocator.checkPermission();
      if (finalPerm == LocationPermission.whileInUse || finalPerm == LocationPermission.always) {
        final userPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );

        final v = widget.venue ??
            (widget.post['venueMap'] is Map ? widget.post['venueMap'] : null) ??
            (widget.post['venue'] is Map ? widget.post['venue'] : null);

        double? vLat = double.tryParse(
          v?['latitude']?.toString() ??
              v?['lat']?.toString() ??
              widget.post['latitude']?.toString() ??
              widget.post['lat']?.toString() ??
              '',
        );
        double? vLng = double.tryParse(
          v?['longitude']?.toString() ??
              v?['lng']?.toString() ??
              widget.post['longitude']?.toString() ??
              widget.post['lng']?.toString() ??
              '',
        );

        if (vLat == null || vLng == null || vLat == 0.0 || vLng == 0.0) {
          // Resolve dynamically from full venue directory
          final venueId = v?['id']?.toString() ??
              v?['venueId']?.toString() ??
              widget.post['venueId']?.toString() ??
              widget.post['targetVenueId']?.toString() ??
              '';
          final venueArea = (v?['area'] ?? widget.post['area'] ?? widget.post['locality'] ?? '')
              .toString()
              .replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '')
              .trim();
          final venueCity = (v?['city'] ?? widget.post['city'] ?? '').toString().trim();
          final venueName = (v?['name'] ?? widget.post['venue'] ?? widget.post['venueName'] ?? '')
              .toString()
              .trim();

          try {
            final allVenues = await ApiService.fetchVenues(city: venueCity.isNotEmpty ? venueCity : null);
            Venue? matched;
            if (venueId.isNotEmpty && venueId != '0') {
              matched = allVenues.where((vn) => vn.id == venueId).firstOrNull;
            }
            if (matched == null && venueName.isNotEmpty && !venueName.toLowerCase().contains('secret venue')) {
              matched = allVenues.where((vn) => vn.name.toLowerCase() == venueName.toLowerCase()).firstOrNull;
            }
            if (matched == null && venueArea.isNotEmpty && !venueArea.toLowerCase().contains('secret location')) {
              matched = allVenues.where((vn) {
                final area = vn.area?.toLowerCase() ?? '';
                final addr = vn.addressLine1.toLowerCase();
                final vAreaLower = venueArea.toLowerCase();
                return area == vAreaLower || addr.contains(vAreaLower);
              }).firstOrNull;
            }
            if (matched != null && matched.latitude != null && matched.longitude != null) {
              vLat = matched.latitude;
              vLng = matched.longitude;
            }
          } catch (err) {
            debugPrint('Error matching venue dynamically for distance: $err');
          }
        }

        if (vLat != null && vLng != null && vLat != 0.0 && vLng != 0.0) {
          final meters = Geolocator.distanceBetween(
            userPos.latitude,
            userPos.longitude,
            vLat,
            vLng,
          );
          if (mounted) {
            setState(() {
              _calculatedDistanceKm = meters / 1000.0;
              _isFetchingDistance = false;
            });
          }
          return;
        }

        // Fallback: If pre-calculated distance string is available on the post
        final rawDistance = widget.post['distance'] ?? v?['distance'];
        if (rawDistance != null) {
          final parsed = double.tryParse(rawDistance.toString().replaceAll(RegExp(r'[^\d.]'), ''));
          if (parsed != null && parsed > 0) {
            if (mounted) {
              setState(() {
                _calculatedDistanceKm = parsed;
                _isFetchingDistance = false;
              });
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching location distance: $e');
    }

    if (mounted) {
      setState(() => _isFetchingDistance = false);
    }
  }

  Widget _buildDistanceOrLocationWidget() {
    if (_calculatedDistanceKm != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.near_me_rounded,
              size: 14,
              color: LunaraTheme.electricViolet,
            ),
            const SizedBox(width: 4),
            Text(
              '${_calculatedDistanceKm!.toStringAsFixed(1)} km away',
              style: const TextStyle(
                color: LunaraTheme.electricViolet,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _fetchActualDistance(showPermissionPrompt: true),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LunaraTheme.purpleGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isFetchingDistance)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 1.5,
                ),
              )
            else
              const Icon(
                Icons.my_location_rounded,
                size: 14,
                color: Colors.white,
              ),
            const SizedBox(width: 6),
            const Text(
              'GET ACTUAL DISTANCE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onStrangersMeetUpdated(dynamic data) {
    if (data is Map) {
      final reqId = data['requestId']?.toString();
      if (reqId == widget.post['id']?.toString()) {
        _loadStrangersMeetDetails(showFullScreenLoader: false);
      }
    }
  }

  @override
  void dispose() {
    RealtimeSyncManager.instance.strangerMeetNotifier.removeListener(_onRealtimePostDetailChanged);
    RealtimeSyncManager.instance.globalSyncTick.removeListener(_onRealtimePostDetailChanged);
    if (!kIsWeb) {
      try {
        _razorpay.clear();
      } catch (e) {
        debugPrint('Razorpay clear error: $e');
      }
    }
    if (widget.post['type'] == 'strangers_meet') {
      ApiService.removeSocketListener(
        'strangers_meet_updated',
        _onStrangersMeetUpdated,
      );
    }
    super.dispose();
  }

  Future<void> _loadStrangersMeetDetails({
    bool showFullScreenLoader = true,
  }) async {
    if (showFullScreenLoader) {
      setState(() => _isLoading = true);
    }
    final rawId = widget.post['requestId'] ??
        widget.post['strangersMeetRequestId'] ??
        widget.post['strangersMeetId'] ??
        widget.post['meetId'] ??
        (widget.post['data'] is Map
            ? widget.post['data']['requestId'] ??
                widget.post['data']['id'] ??
                widget.post['data']['strangersMeetRequestId']
            : null) ??
        (widget.post['plan'] is Map
            ? widget.post['plan']['id'] ?? widget.post['plan']['requestId']
            : null) ??
        (widget.post['request'] is Map ? widget.post['request']['id'] : null) ??
        widget.post['id'] ??
        widget.post['entityId'];

    StrangersMeetRequest? req;
    if (rawId != null && rawId.toString().trim().isNotEmpty) {
      String cleanId = rawId.toString().trim();
      cleanId = cleanId.replaceAll(RegExp(r'^(sm_host_approved_|sm_join_|sm_meet_|sm_|stranger_meet_|strangers_meet_|notification_|notif_)'), '');
      req = await ApiService.fetchStrangersMeetRequestById(cleanId);
      if (req == null && cleanId != rawId.toString().trim()) {
        req = await ApiService.fetchStrangersMeetRequestById(rawId.toString().trim());
      }
    }

    if (req == null) {
      try {
        final Map<String, dynamic> postData = Map<String, dynamic>.from(widget.post);
        if (postData['plan'] is Map) {
          postData.addAll(Map<String, dynamic>.from(postData['plan']));
        }
        req = StrangersMeetRequest.fromJson(postData);
      } catch (e) {
        debugPrint('Error fallback parsing StrangersMeetRequest: $e');
      }
    }

    if (mounted) {
      final currentUid = ApiService.currentUserId ?? '';
      bool userRequested = _alreadyRequested;
      if (req?.joiners != null) {
        for (var j in req!.joiners!) {
          if (j is Map && (j['userId']?.toString() == currentUid || j['id']?.toString() == currentUid)) {
            final st = (j['status'] ?? '').toString().toLowerCase();
            if (st != 'rejected' && st != 'cancelled' && st != 'declined') {
              userRequested = true;
            }
            break;
          }
        }
      }
      setState(() {
        _meetRequest = req;
        _alreadyRequested = userRequested;
        _isLoading = false;
      });
    }
  }

  // ─── Razorpay Payment Handlers ─────────────────────────────────────────────
  void _handleRazorpaySuccess(PaymentSuccessResponse response) {
    _confirmJoinPayment(
      response.orderId ?? _lastOrderId ?? 'mock_order',
      response.paymentId ?? 'mock_payment',
      response.signature ?? 'mock_signature',
    );
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() => _isProcessing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External Wallet: ${response.walletName}')),
    );
  }

  Future<void> _confirmJoinPayment(
    String orderId,
    String paymentId,
    String signature,
  ) async {
    final req = _meetRequest;
    if (req == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ApiService.payStrangersMeetJoin(
      req.id,
      orderId,
      paymentId,
      signature,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result != null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Successfully joined strangers meet! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
      _loadStrangersMeetDetails(showFullScreenLoader: false);
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Verification failed. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Future<void> _sendJoinRequest() async {
    if (_meetRequest == null) return;
    await _showPreferencesBottomSheet(context);
  }

  Future<void> _showPreferencesBottomSheet(BuildContext context) async {
    String foodPref = 'Both';
    String drinkPref = 'Both';

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setStateSheet) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                24 + MediaQuery.of(ctx2).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'SELECT PREFERENCES',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please share your food and drink preferences with the host.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),

                  // Food preference dropdown
                  const Text(
                    'Food Preference',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        initialValue: foodPref,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(
                            Icons.restaurant,
                            color: LunaraTheme.electricViolet,
                            size: 18,
                          ),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 28,
                            minHeight: 18,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        items: const ['Veg', 'Non-Veg', 'Both'].map((
                          String val,
                        ) {
                          return DropdownMenuItem<String>(
                            value: val,
                            child: Text(
                              val,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setStateSheet(() => foodPref = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Drink preference dropdown
                  const Text(
                    'Drink Preference',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        initialValue: drinkPref,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(
                            Icons.local_bar,
                            color: LunaraTheme.electricViolet,
                            size: 18,
                          ),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 28,
                            minHeight: 18,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        items: const ['Alcoholic', 'Non-Alcoholic', 'Both'].map(
                          (String val) {
                            return DropdownMenuItem<String>(
                              value: val,
                              child: Text(
                                val,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          },
                        ).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setStateSheet(() => drinkPref = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Proceed Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx, {
                          'food': foodPref,
                          'drink': drinkPref,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'SUBMIT REQUEST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      await _sendJoinRequestWithPreferences(result['food']!, result['drink']!);
    }
  }

  Future<void> _sendJoinRequestWithPreferences(
    String foodPref,
    String drinkPref,
  ) async {
    final req = _meetRequest;
    if (req == null) return;

    if (!OptimisticActionGuard.start('JOIN_MEET:${req.id}')) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final success = await ApiService.sendStrangersMeetJoinRequest(
        req.id,
        foodPreference: foodPref,
        drinkPreference: drinkPref,
      );
      if (!mounted) return;

      if (success) {
        setState(() {
          _alreadyRequested = true;
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Join request sent successfully! Waiting for host approval. 🤞',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadStrangersMeetDetails(showFullScreenLoader: false);
      } else {
        setState(() {
          _alreadyRequested = false;
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send join request. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _alreadyRequested = false;
          _isProcessing = false;
        });
        if (TimeLockBlockedDialog.isConflictError(e)) {
          TimeLockBlockedDialog.showWithMessage(context, e.toString());
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TimeLockBlockedDialog.cleanErrorMessage(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      OptimisticActionGuard.end('JOIN_MEET:${req.id}');
    }
  }

  Future<void> _completeMeetFlow() async {
    if (_meetRequest == null) return;

    final messenger = ScaffoldMessenger.of(context);

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Meet'),
        content: const Text(
          'Are you sure you want to mark this Strangers Meet as successfully completed? This action is permanent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
            ),
            child: const Text(
              'COMPLETE',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || _meetRequest == null) return;
    setState(() => _isProcessing = true);
    final success = await ApiService.completeStrangersMeet(_meetRequest!.id);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Strangers meet marked as completed! 🏆'),
          backgroundColor: Colors.green,
        ),
      );
      _loadStrangersMeetDetails();
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to complete strangers meet.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
        ),
      );
    }

    if (widget.post['type'] == 'strangers_meet') {
      if (_meetRequest == null) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'STRANGER MEET',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline_rounded, color: LunaraTheme.electricViolet, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Stranger Meet details unavailable or request pending.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _loadStrangersMeetDetails(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('RETRY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return _buildStrangersMeetDetails();
    } else {
      return _buildPartyPlanDetails();
    }
  }

  // ─── Strangers Meet Details Layout ─────────────────────────────────────────
  Widget _buildStrangersMeetDetails() {
    final req = _meetRequest;
    if (req == null) return const SizedBox.shrink();
    final String subject = req.subject;
    final String tagline = req.tagline;
    final double charges = req.chargesPerHead;
    final int slotsFilled = req.slotsFilled;
    int maxPersons = req.numberOfPersons;
    if (maxPersons <= 0 || maxPersons == 2) {
      final rawMax = widget.post['numberOfPersons'] ??
          widget.post['number_of_persons'] ??
          widget.post['totalSeats'] ??
          widget.post['maxPersons'] ??
          widget.post['seats'] ??
          widget.post['maxSeats'] ??
          widget.post['numberOfGuests'] ??
          (widget.post['plan'] is Map ? widget.post['plan']['numberOfPersons'] ?? widget.post['plan']['totalSeats'] ?? widget.post['plan']['maxPersons'] : null);
      if (rawMax != null) {
        maxPersons = int.tryParse(rawMax.toString()) ?? maxPersons;
      }
    }
    final String rawVenueName = req.venue?['name'] ??
        widget.venue?['name'] ??
        (widget.post['venue'] is Map ? widget.post['venue']['name']?.toString() : null) ??
        (widget.post['venue'] is String ? widget.post['venue']?.toString() : null) ??
        widget.post['venueName']?.toString() ??
        'Unknown Venue';

    final cachedUser = ApiService.cachedCurrentUser;
    Map<String, dynamic> hostUserMap = req.user != null && req.user!.isNotEmpty
        ? Map<String, dynamic>.from(req.user!)
        : (widget.post['user'] is Map
            ? Map<String, dynamic>.from(widget.post['user'])
            : (widget.post['creator'] is Map
                ? Map<String, dynamic>.from(widget.post['creator'])
                : (widget.post['host'] is Map
                    ? Map<String, dynamic>.from(widget.post['host'])
                    : {})));

    final String currentUserId = ApiService.currentUserId ?? '';
    final bool isMyPost =
        (req.userId != null && req.userId.toString() == currentUserId) ||
        (hostUserMap['id'] != null && hostUserMap['id']?.toString() == currentUserId) ||
        (widget.post['userId'] != null && widget.post['userId']?.toString() == currentUserId) ||
        (widget.post['user_id'] != null && widget.post['user_id']?.toString() == currentUserId) ||
        (widget.post['creatorId'] != null && widget.post['creatorId']?.toString() == currentUserId) ||
        (widget.post['creator'] != null && widget.post['creator']['id']?.toString() == currentUserId) ||
        (widget.post['user'] != null && widget.post['user']['id']?.toString() == currentUserId) ||
        (widget.post['plan'] is Map && widget.post['plan']['userId']?.toString() == currentUserId);

    if (isMyPost && cachedUser != null) {
      if (hostUserMap['firstName'] == null || hostUserMap['firstName'].toString().isEmpty || hostUserMap['firstName'] == 'Lunara') {
        hostUserMap['firstName'] = cachedUser.firstName;
        hostUserMap['lastName'] = cachedUser.lastName;
        hostUserMap['photoUrl'] = hostUserMap['photoUrl'] ?? cachedUser.profilePhoto;
        hostUserMap['profileImageUrl'] = hostUserMap['profileImageUrl'] ?? cachedUser.profilePhoto;
      }
    }

    String fn = (hostUserMap['firstName'] ?? hostUserMap['first_name'] ?? '').toString().trim();
    String ln = (hostUserMap['lastName'] ?? hostUserMap['last_name'] ?? '').toString().trim();
    if ((fn.isEmpty || fn == 'Lunara') && hostUserMap['fullName'] != null && hostUserMap['fullName'].toString().trim().isNotEmpty) {
      final parts = hostUserMap['fullName'].toString().trim().split(' ');
      fn = parts.first;
      ln = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    if ((fn.isEmpty || fn == 'Lunara') && hostUserMap['name'] != null && hostUserMap['name'].toString().trim().isNotEmpty) {
      final parts = hostUserMap['name'].toString().trim().split(' ');
      fn = parts.first;
      ln = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    if ((fn.isEmpty || fn == 'Lunara') && isMyPost && cachedUser != null) {
      fn = cachedUser.firstName;
      ln = cachedUser.lastName;
    }

    final String hostFirstName = fn.isNotEmpty ? fn : 'Lunara';
    final String hostLastName = ln.isNotEmpty ? ln : (fn != 'Lunara' ? '' : 'User');
    final String? hostPhoto = hostUserMap['photoUrl'] ??
        hostUserMap['profileImageUrl'] ??
        hostUserMap['profilePhotoUrl'] ??
        hostUserMap['photo'] ??
        (isMyPost && cachedUser != null ? cachedUser.profilePhoto : null);

    Map<String, dynamic>? myJoinerInfo;
    if (req.joiners != null) {
      for (var j in req.joiners!) {
        if (j is Map &&
            (j['userId']?.toString() == currentUserId ||
                j['id']?.toString() == currentUserId)) {
          myJoinerInfo = Map<String, dynamic>.from(j);
          break;
        }
      }
    }

    final bool isSecretVenue = widget.post['showVenueDetails'] == false ||
        widget.post['isSecret'] == true ||
        widget.post['isSecretVenue'] == true ||
        req.venue?['showVenueDetails'] == false ||
        req.venue?['isSecret'] == true ||
        req.venue?['isSecretVenue'] == true ||
        widget.venue?['showVenueDetails'] == false ||
        widget.venue?['isSecret'] == true ||
        widget.venue?['isSecretVenue'] == true ||
        req.venue?['name']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        widget.venue?['name']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        widget.post['venue']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        widget.post['venueName']?.toString().toUpperCase().contains('SECRET VENUE') == true;
    final bool hasConfirmedBooking = myJoinerInfo != null &&
        (myJoinerInfo['paymentStatus'] == 'paid' ||
            myJoinerInfo['status'] == 'CONFIRMED' ||
            myJoinerInfo['status'] == 'APPROVED');
    final bool hideVenue = isSecretVenue && !isMyPost && !hasConfirmedBooking;
    final String venueName = hideVenue ? 'SECRET VENUE 🔒' : rawVenueName;

    final isFastFilling = slotsFilled >= 2;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(
            context,
            hostFirstName,
            hostLastName,
            DateFormat('MMM dd, hh:mm a').format(req.eventDateTime),
            hostPhoto,
            widget.post,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),

                  // Subject/Title & Fast Filling Tag
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subject,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (isFastFilling) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.orange, Colors.redAccent],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.whatshot,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'FAST FILLING',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tagline / Details
                  Text(
                    tagline,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Event Metadata Info Row
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Venue details
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: (hideVenue ? Colors.amber : LunaraTheme.electricViolet).withValues(
                                      alpha: 0.1,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    hideVenue ? Icons.lock_outline_rounded : Icons.location_on_rounded,
                                    color: hideVenue ? Colors.amber[800] : LunaraTheme.electricViolet,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hideVenue ? 'VENUE PRIVACY' : 'HAPPENING AT',
                                        style: const TextStyle(
                                          color: Colors.black38,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        venueName.toUpperCase(),
                                        style: TextStyle(
                                          color: hideVenue ? Colors.amber[900] : Colors.black,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!hideVenue && widget.venue != null)
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => VenueDetailScreen(
                                            venue: widget.venue!,
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'VIEW',
                                      style: TextStyle(
                                        color: LunaraTheme.electricViolet,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (hideVenue) ...[
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.only(left: 44),
                                child: Text(
                                  'Locality: ${widget.venue?['area'] ?? widget.venue?['city'] ?? widget.post['area'] ?? widget.post['city'] ?? 'Local Area'} (Exact venue revealed once host approves)',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.only(left: 44),
                                child: _buildDistanceOrLocationWidget(),
                              ),
                            ],
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(),
                        ),
                        // Charges details
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.currency_rupee_rounded,
                                color: Colors.green,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'CHARGES PER HEAD',
                                    style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    charges > 0
                                        ? '₹${charges.toStringAsFixed(0)}'
                                        : 'FREE ENTRY',
                                    style: TextStyle(
                                      color: charges > 0
                                          ? Colors.black
                                          : Colors.green,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(),
                        ),
                        // Slots Filled details
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.people_alt_rounded,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SLOTS FILLED',
                                    style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    '$slotsFilled / $maxPersons joined',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Host Details Card
                  const SizedBox(height: 24),
                  const Text(
                    'HOST',
                    style: TextStyle(
                      color: Colors.black38,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      User? profileUser;
                      try {
                        profileUser = User.fromJson(hostUserMap);
                      } catch (_) {}
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(user: profileUser),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[100]!),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: LunaraTheme.electricViolet
                                .withValues(alpha: 0.1),
                            backgroundImage:
                                hostPhoto != null && hostPhoto.trim().isNotEmpty
                                ? NetworkImage(
                                    hostPhoto.startsWith('http')
                                        ? hostPhoto
                                        : (hostPhoto.startsWith('/')
                                            ? '${ApiService.baseUrl}$hostPhoto'
                                            : '${ApiService.baseUrl}/$hostPhoto'),
                                  )
                                : null,
                            child: hostPhoto == null || hostPhoto.trim().isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: LunaraTheme.electricViolet,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$hostFirstName $hostLastName',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                if (hostUserMap['bio'] != null &&
                                    hostUserMap['bio'].toString().isNotEmpty)
                                  Text(
                                    hostUserMap['bio'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                  // Pending Requests Section (only for Host)
                  if (isMyPost) ...[_buildPendingRequestsSection(slotsFilled, maxPersons)],

                  // Participants Section
                  _buildParticipantsSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: _buildStrangersMeetActionButton(
            isMyPost,
            myJoinerInfo,
            slotsFilled,
            maxPersons,
            req.status,
            req.eventDateTime,
            charges,
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantsSection() {
    final rawJoiners = (_meetRequest?.joiners ?? []).whereType<Map>().toList();
    final allJoiners = rawJoiners.map((j) {
      final id = j['id']?.toString() ?? '';
      if (_optimisticJoinerStatus.containsKey(id)) {
        final copy = Map<String, dynamic>.from(j);
        copy['status'] = _optimisticJoinerStatus[id];
        return copy;
      }
      return j;
    }).toList();

    // 1. Actual Joined — paid participants
    final actualJoined = allJoiners.where((j) {
      final status = (j['status'] ?? '').toString().toLowerCase();
      final payStatus = (j['paymentStatus'] ?? '').toString().toLowerCase();
      return status == 'paid' || payStatus == 'paid';
    }).toList();

    // 2. People Joining — accepted by host, awaiting payment
    final peopleJoining = allJoiners.where((j) {
      final status = (j['status'] ?? '').toString().toLowerCase();
      final payStatus = (j['paymentStatus'] ?? '').toString().toLowerCase();
      final bool isPaid = status == 'paid' || payStatus == 'paid';
      return !isPaid && (status == 'accepted' || status == 'confirmed' || payStatus == 'pending');
    }).toList();

    if (actualJoined.isEmpty && peopleJoining.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. ACTUAL JOINED (PAID) SECTION ──────────────────────────────────
        if (actualJoined.isNotEmpty) ...[
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PEOPLE JOINED (${actualJoined.length})',
                style: const TextStyle(
                  color: Colors.black38,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 10, color: Colors.green),
                    SizedBox(width: 4),
                    Text(
                      'PAID & CONFIRMED',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: actualJoined.length,
              itemBuilder: (context, index) {
                return _buildParticipantItem(actualJoined[index], isPaid: true);
              },
            ),
          ),
        ],

        // ── 2. PEOPLE JOINING (ACCEPTED) SECTION ─────────────────────────────
        if (peopleJoining.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PEOPLE JOINING (${peopleJoining.length})',
                style: const TextStyle(
                  color: Colors.black38,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.how_to_reg_rounded, size: 10, color: LunaraTheme.electricViolet),
                    SizedBox(width: 4),
                    Text(
                      'ACCEPTED',
                      style: TextStyle(
                        color: LunaraTheme.electricViolet,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: peopleJoining.length,
              itemBuilder: (context, index) {
                return _buildParticipantItem(peopleJoining[index], isPaid: false);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildParticipantItem(Map<dynamic, dynamic> joiner, {required bool isPaid}) {
    final ju = joiner['user'] as Map<String, dynamic>?;
    if (ju == null) return const SizedBox.shrink();

    final name = ju['firstName'] ?? 'User';
    final photo = ju['photoUrl'] ?? ju['profileImageUrl'];
    String? finalPhoto = photo;
    if (finalPhoto != null &&
        finalPhoto.startsWith('/') &&
        !finalPhoto.startsWith('assets')) {
      finalPhoto = '${ApiService.baseUrl}$finalPhoto';
    }

    return GestureDetector(
      onTap: () {
        User? profileUser;
        try {
          profileUser = User.fromJson(ju);
        } catch (_) {}
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(user: profileUser),
          ),
        );
      },
      child: Container(
        width: 70,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: LunaraTheme.electricViolet.withValues(
                    alpha: 0.08,
                  ),
                  backgroundImage:
                      finalPhoto != null && finalPhoto.isNotEmpty
                      ? NetworkImage(finalPhoto)
                      : null,
                  child: finalPhoto == null || finalPhoto.isEmpty
                      ? const Icon(
                          Icons.person,
                          color: LunaraTheme.electricViolet,
                        )
                      : null,
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isPaid ? Colors.green : LunaraTheme.electricViolet,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Icon(
                      isPaid ? Icons.check : Icons.hourglass_empty_rounded,
                      color: Colors.white,
                      size: 9,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingRequestsSection(int slotsFilled, int maxPersons) {
    final rawJoiners = (_meetRequest?.joiners ?? []).whereType<Map>().toList();
    if (rawJoiners.isEmpty) {
      return const SizedBox.shrink();
    }

    final allJoiners = rawJoiners.map((j) {
      final id = j['id']?.toString() ?? '';
      if (_optimisticJoinerStatus.containsKey(id)) {
        final copy = Map<String, dynamic>.from(j);
        copy['status'] = _optimisticJoinerStatus[id];
        return copy;
      }
      return j;
    }).toList();

    final bool isFull = slotsFilled >= maxPersons;
    final int availableSlots = (maxPersons - slotsFilled).clamp(0, maxPersons);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'JOIN REQUESTS (${allJoiners.length})',
              style: const TextStyle(
                color: Colors.black38,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isFull ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isFull ? 'MEET FULL ($slotsFilled/$maxPersons)' : '$availableSlots spots remaining',
                style: TextStyle(
                  color: isFull ? Colors.red : Colors.green[700],
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (isFull) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All spots are filled! You can decline remaining requests or wait if someone cancels.',
                    style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: allJoiners.length,
          itemBuilder: (context, index) {
            final joiner = allJoiners[index];
            final ju = (joiner['user'] is Map)
                ? joiner['user'] as Map<String, dynamic>
                : (joiner['requester'] is Map ? joiner['requester'] as Map<String, dynamic> : <String, dynamic>{});

            final name = '${ju['firstName'] ?? 'User'} ${ju['lastName'] ?? ''}'.trim();
            final photo = ju['photoUrl'] ?? ju['profileImageUrl'];
            String? finalPhoto = photo;
            if (finalPhoto != null &&
                finalPhoto.startsWith('/') &&
                !finalPhoto.startsWith('assets')) {
              finalPhoto = '${ApiService.baseUrl}$finalPhoto';
            }

            final joinerId = joiner['id'].toString();
            final bio = ju['bio']?.toString() ?? ju['profile']?['bio']?.toString();
            final foodPref = joiner['foodPreference']?.toString() ?? ju['foodPreference']?.toString();
            final drinkPref = joiner['drinkPreference']?.toString() ?? ju['drinkPreference']?.toString();

            final status = (joiner['status'] ?? 'pending').toString().toLowerCase();
            final payStatus = (joiner['paymentStatus'] ?? '').toString().toLowerCase();
            final isPaid = status == 'paid' || payStatus == 'paid';
            final isAccepted = status == 'accepted' || status == 'confirmed' || payStatus == 'pending';
            final isRejected = status == 'rejected' || status == 'declined';
            final isCancelled = status == 'cancelled';

            final acceptKey = '$joinerId:accept';
            final declineKey = '$joinerId:reject';
            final isAccepting = _loadingJoinerActions.contains(acceptKey);
            final isDeclining = _loadingJoinerActions.contains(declineKey);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: LunaraTheme.electricViolet.withValues(
                          alpha: 0.08,
                        ),
                        backgroundImage: finalPhoto != null && finalPhoto.isNotEmpty
                            ? NetworkImage(finalPhoto)
                            : null,
                        child: finalPhoto == null || finalPhoto.isEmpty
                            ? const Icon(
                                Icons.person,
                                color: LunaraTheme.electricViolet,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'Lunara Member' : name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (bio != null && bio.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  bio,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (foodPref != null || drinkPref != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  'Food: ${foodPref ?? "Any"} • Drink: ${drinkPref ?? "Any"}',
                                  style: const TextStyle(
                                    color: LunaraTheme.electricViolet,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isPaid)
                    _buildJoinerStatusBadge(
                      'Paid & Confirmed',
                      Colors.green,
                      Icons.check_circle_rounded,
                    )
                  else if (isAccepted)
                    _buildJoinerStatusBadge(
                      'Accepted • Awaiting Payment',
                      LunaraTheme.electricViolet,
                      Icons.hourglass_top_rounded,
                    )
                  else if (isRejected)
                    _buildJoinerStatusBadge(
                      'Declined',
                      Colors.redAccent,
                      Icons.cancel_rounded,
                    )
                  else if (isCancelled)
                    _buildJoinerStatusBadge(
                      'Cancelled',
                      Colors.grey,
                      Icons.cancel_outlined,
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (isFull || isAccepting || isDeclining)
                                ? null
                                : () => _handleRequest(joinerId, 'accept'),
                            icon: isAccepting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_rounded, size: 16),
                            label: Text(
                              isAccepting ? 'Approving...' : 'Approve',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: LunaraTheme.electricViolet,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[300],
                              disabledForegroundColor: Colors.grey[600],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (isAccepting || isDeclining)
                                ? null
                                : () => _handleRequest(joinerId, 'reject'),
                            icon: isDeclining
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.redAccent,
                                    ),
                                  )
                                : const Icon(
                                    Icons.cancel_rounded,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                            label: Text(
                              isDeclining ? 'Declining...' : 'Decline',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.redAccent,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0x40EF4444)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
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
      ],
    );
  }

  Widget _buildJoinerStatusBadge(String text, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRequest(String joinerId, String action) async {
    final req = _meetRequest;
    if (req == null) return;

    final actionKey = '$joinerId:$action';
    if (_loadingJoinerActions.contains(actionKey)) return;
    setState(() => _loadingJoinerActions.add(actionKey));

    if (!OptimisticActionGuard.start('HANDLE_MEET_REQ:${req.id}:$joinerId')) {
      setState(() => _loadingJoinerActions.remove(actionKey));
      return;
    }

    final prevStatus = _optimisticJoinerStatus[joinerId];

    // Optimistic UI: immediately update joiner status locally
    setState(() {
      _optimisticJoinerStatus[joinerId] = action == 'accept' ? 'accepted' : 'rejected';
      _isProcessing = false;
    });

    try {
      final success = await ApiService.handleStrangersMeetJoinRequest(
        req.id,
        joinerId,
        action,
      );
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'accept'
                  ? 'Join request accepted!'
                  : 'Join request declined.',
            ),
            backgroundColor: action == 'accept' ? Colors.green : Colors.grey[800],
          ),
        );
        _loadStrangersMeetDetails(showFullScreenLoader: false);
      } else {
        // Rollback
        setState(() {
          if (prevStatus != null) {
            _optimisticJoinerStatus[joinerId] = prevStatus;
          } else {
            _optimisticJoinerStatus.remove(joinerId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to handle join request. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (prevStatus != null) {
            _optimisticJoinerStatus[joinerId] = prevStatus;
          } else {
            _optimisticJoinerStatus.remove(joinerId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingJoinerActions.remove(actionKey));
      }
      OptimisticActionGuard.end('HANDLE_MEET_REQ:${req.id}:$joinerId');
    }
  }

  void _showParticipantsChatModal(List<dynamic> joiners, String meetId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF161622) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Chat with Participants',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: joiners.length,
                    separatorBuilder: (context, i) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final j = joiners[idx];
                      final ju = j['user'] as Map<String, dynamic>? ?? {};
                      final jId = j['userId'] ?? ju['id'] ?? j['id'];
                      final jName = ju['firstName'] ?? j['firstName'] ?? 'Participant';
                      final jLastName = ju['lastName'] ?? j['lastName'] ?? '';
                      final jPhoto = ju['profilePhotoUrl'] ?? ju['photoUrl'] ?? ju['profileImageUrl'] ?? j['photoUrl'];

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                          backgroundImage: jPhoto != null && jPhoto.toString().isNotEmpty
                              ? NetworkImage(
                                  jPhoto.toString().startsWith('http')
                                      ? jPhoto.toString()
                                      : (jPhoto.toString().startsWith('/')
                                          ? '${ApiService.baseUrl}$jPhoto'
                                          : '${ApiService.baseUrl}/$jPhoto'),
                                )
                              : null,
                          child: jPhoto == null || jPhoto.toString().isEmpty
                              ? const Icon(Icons.person, color: LunaraTheme.electricViolet)
                              : null,
                        ),
                        title: Text(
                          '$jName $jLastName'.trim(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        trailing: const Icon(Icons.chat_bubble_outline_rounded, color: LunaraTheme.electricViolet),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                user: {
                                  'id': jId?.toString() ?? '',
                                  'firstName': jName.toString(),
                                  'lastName': jLastName.toString(),
                                  'profilePhotoUrl': jPhoto?.toString(),
                                  'contextType': 'strangers_meet',
                                  'planId': meetId,
                                },
                              ),
                            ),
                          );
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
  }

  Widget _buildStrangersMeetActionButton(
    bool isMyPost,
    Map<String, dynamic>? myJoinerInfo,
    int slotsFilled,
    int maxPersons,
    String status,
    DateTime eventDateTime,
    double charges,
  ) {
    if (_isProcessing) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
        ),
      );
    }

    final req = _meetRequest;
    final String reqStatus = (req?.status.isNotEmpty == true
            ? req!.status
            : (widget.post['status'] ?? widget.post['plan']?['status'] ?? widget.post['request']?['status'] ?? status))
        .toString()
        .toLowerCase();
    final String payStatus = (req?.paymentStatus.isNotEmpty == true
            ? req!.paymentStatus
            : (widget.post['paymentStatus'] ?? widget.post['payment_status'] ?? widget.post['plan']?['paymentStatus'] ?? ''))
        .toString()
        .toLowerCase();
    final String hostPayStatus = (widget.post['hostPaymentStatus'] ?? widget.post['host_payment_status'] ?? '').toString().toLowerCase();

    final bool isDepositPaid = payStatus == 'paid' ||
        hostPayStatus == 'paid' ||
        reqStatus == 'confirmed' ||
        reqStatus == 'live' ||
        reqStatus == 'completed';

    final double depositAmount = req?.paymentAmount ??
        (widget.post['paymentAmount'] is num
            ? (widget.post['paymentAmount'] as num).toDouble()
            : (double.tryParse((widget.post['paymentAmount'] ?? '99').toString()) ?? 99.0));

    final now = DateTime.now();
    final bool hasEnded = now.isAfter(eventDateTime);

    if (isMyPost) {
      // ───────────────────────────────────────────────────────────────────────
      // HOST VIEW (Current user is the creator of this Stranger Meet)
      // ───────────────────────────────────────────────────────────────────────
      if (reqStatus == 'pending' || reqStatus == 'request_sent' || reqStatus == 'pending_approval') {
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_top_rounded, color: Color(0xFF8B5CF6)),
                SizedBox(width: 8),
                Text(
                  'WAITING FOR ADMIN APPROVAL',
                  style: TextStyle(
                    fontFamily: 'AllroundGothic',
                    color: Color(0xFF8B5CF6),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (!isDepositPaid && (reqStatus == 'approved' || reqStatus == 'accepted' || reqStatus == 'payment_pending' || payStatus != 'paid')) {
        // Admin approved! Host must pay deposit to publish meet
        final feeLabel = depositAmount > 0 ? ' ₹${depositAmount.toStringAsFixed(0)}' : '';
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            gradient: LunaraTheme.purpleGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () {
              final targetReq = req ?? StrangersMeetRequest.fromJson(Map<String, dynamic>.from(widget.post));
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetPaymentScreen(
                    request: targetReq,
                    onPaymentSuccess: () => _loadStrangersMeetDetails(showFullScreenLoader: false),
                    isJoinPayment: false,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: const Icon(Icons.payment_rounded, color: Colors.white),
            label: Text(
              'PAY DEPOSIT$feeLabel',
              style: const TextStyle(
                fontFamily: 'AllroundGothic',
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } else if (hasEnded) {
        if (reqStatus == 'completed') {
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green),
            ),
            child: const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'MEET COMPLETED SUCCESS',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              gradient: LunaraTheme.purpleGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFb952eb).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _completeMeetFlow,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.done_all_rounded, color: Colors.white),
              label: const Text(
                'COMPLETE MEET',
                style: TextStyle(
                  fontFamily: 'AllroundGothic',
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }
      } else {
        // Host Deposit Paid & Event Live / Confirmed -> Show CHAT and VIEW TICKET
        final targetReq = req ?? StrangersMeetRequest.fromJson(Map<String, dynamic>.from(widget.post));
        return Row(
          children: [
            Expanded(
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: LunaraTheme.purpleGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFb952eb).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    final joiners = (targetReq.joiners ?? []).where((j) {
                      if (j is Map) {
                        final st = j['status']?.toString().toLowerCase();
                        final ps = j['paymentStatus']?.toString().toLowerCase();
                        return st == 'accepted' || st == 'paid' || ps == 'paid' || st == 'confirmed';
                      }
                      return false;
                    }).toList();

                    if (joiners.length == 1) {
                      final j = joiners.first;
                      final ju = j['user'] as Map<String, dynamic>? ?? {};
                      final jId = j['userId'] ?? ju['id'] ?? j['id'];
                      final jName = ju['firstName'] ?? j['firstName'] ?? 'Participant';
                      final jLastName = ju['lastName'] ?? j['lastName'] ?? '';
                      final jPhoto = ju['profilePhotoUrl'] ?? ju['photoUrl'] ?? ju['profileImageUrl'] ?? j['photoUrl'];
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            user: {
                              'id': jId?.toString() ?? '',
                              'firstName': jName.toString(),
                              'lastName': jLastName.toString(),
                              'profilePhotoUrl': jPhoto?.toString(),
                              'contextType': 'strangers_meet',
                              'planId': targetReq.id,
                            },
                          ),
                        ),
                      );
                    } else if (joiners.length > 1) {
                      _showParticipantsChatModal(joiners, targetReq.id);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No participants have joined this meet yet. Chat unlocks when participants confirm!'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    'CHAT',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StrangersMeetTicketScreen(request: targetReq),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.confirmation_number_rounded, color: Colors.black87, size: 20),
                  label: const Text(
                    'VIEW TICKET',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
    } else {
      // ───────────────────────────────────────────────────────────────────────
      // JOINER / VISITOR VIEW
      // ───────────────────────────────────────────────────────────────────────
      if (!isDepositPaid) {
        // Host has not paid deposit or admin has not approved yet
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              'WAITING FOR HOST DEPOSIT',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }

      if (reqStatus == 'completed' || hasEnded) {
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              'MEET ENDED',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }

      if (myJoinerInfo != null) {
        final jStatus = (myJoinerInfo['status'] ?? '').toString().toLowerCase();
        final jPayStatus = (myJoinerInfo['paymentStatus'] ?? '').toString().toLowerCase();

        if (jStatus == 'paid' || jPayStatus == 'paid') {
          final targetReq = req ?? StrangersMeetRequest.fromJson(Map<String, dynamic>.from(widget.post));
          return Row(
            children: [
              Expanded(
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LunaraTheme.purpleGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFb952eb).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final hostUser = (req?.user != null && req!.user!.isNotEmpty)
                          ? req.user!
                          : (widget.post['user'] is Map
                              ? (widget.post['user'] as Map)
                              : (widget.post['creator'] is Map
                                  ? (widget.post['creator'] as Map)
                                  : (widget.post['host'] is Map ? (widget.post['host'] as Map) : {})));
                      final hostId = req?.userId ?? hostUser['id'] ?? widget.post['userId'] ?? widget.post['creatorId'];
                      final hostFn = (hostUser['firstName'] ?? hostUser['name'] ?? 'Host').toString();
                      final hostLn = (hostUser['lastName'] ?? '').toString();
                      final hostPhotoUrl = (hostUser['photoUrl'] ?? hostUser['profilePhotoUrl'] ?? hostUser['profileImageUrl'])?.toString();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            user: {
                              'id': hostId?.toString() ?? '',
                              'firstName': hostFn,
                              'lastName': hostLn,
                              'profilePhotoUrl': hostPhotoUrl,
                              'contextType': 'strangers_meet',
                              'planId': targetReq.id,
                            },
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'CHAT',
                      style: TextStyle(
                        fontFamily: 'AllroundGothic',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StrangersMeetTicketScreen(request: targetReq),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.confirmation_number_rounded, color: Colors.black87, size: 20),
                    label: const Text(
                      'VIEW TICKET',
                      style: TextStyle(
                        fontFamily: 'AllroundGothic',
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        } else if (jStatus == 'accepted') {
          final feeLabel = charges > 0 ? ' ₹${charges.toStringAsFixed(0)}' : '';
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              gradient: LunaraTheme.purpleGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFb952eb).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                if (req != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StrangersMeetPaymentScreen(
                        request: req,
                        onPaymentSuccess: () => _loadStrangersMeetDetails(showFullScreenLoader: false),
                        isJoinPayment: true,
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.payment_rounded, color: Colors.white),
              label: Text(
                'PAY ENTRY FEE$feeLabel',
                style: const TextStyle(
                  fontFamily: 'AllroundGothic',
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        } else if (jStatus == 'pending' || jStatus == 'requested') {
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'JOIN REQUEST PENDING APPROVAL',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      if (_alreadyRequested) {
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text(
                  'JOIN REQUEST PENDING APPROVAL',
                  style: TextStyle(
                    fontFamily: 'AllroundGothic',
                    color: Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Not requested to join yet
      final bool isFull = slotsFilled >= maxPersons;
      if (isFull) {
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              'MEET FULL',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }

      final feeLabel = charges > 0 ? ' (₹${charges.toStringAsFixed(0)})' : '';
      return Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          gradient: LunaraTheme.purpleGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFb952eb).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: (_isProcessing || _alreadyRequested) ? null : _sendJoinRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          icon: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.person_add_rounded, color: Colors.white),
          label: Text(
            _isProcessing ? 'SENDING REQUEST...' : 'REQUEST TO JOIN$feeLabel',
            style: const TextStyle(
              fontFamily: 'AllroundGothic',
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
  }

  // ─── Party Plan (Normal Post) Details Layout ───────────────────────────────
  Widget _buildPartyPlanDetails() {
    final String firstName = widget.post['firstName'] ?? 'Lunara';
    final String lastName = widget.post['lastName'] ?? 'User';
    final String rawVenueName = (widget.post['venue'] is String ? widget.post['venue'] as String : null) ??
        (widget.post['venue'] is Map ? widget.post['venue']['name']?.toString() : null) ??
        (widget.post['venueMap'] is Map ? widget.post['venueMap']['name']?.toString() : null) ??
        widget.venue?['name']?.toString() ??
        widget.post['venueName']?.toString() ??
        'Unknown Venue';

    final bool isMyPost =
        widget.post['userId']?.toString() == ApiService.currentUserId ||
        (widget.post['user'] != null &&
            widget.post['user']['id']?.toString() == ApiService.currentUserId);
    // canSeeVenue is authoritative from the backend (host, or accepted joiner).
    // Fall back to the old client-side signals for Strangers Meet posts, which
    // don't carry canSeeVenue.
    final bool hasConfirmedBooking = widget.post['canSeeVenue'] == true ||
        widget.post['hasConfirmedBooking'] == true ||
        widget.post['isMatched'] == true ||
        _alreadyRequested && (_meetRequest?.joiners != null);
    final bool isSecretVenue = widget.post['showVenueDetails'] == false ||
        widget.post['isSecret'] == true ||
        widget.post['isSecretVenue'] == true ||
        widget.venue?['showVenueDetails'] == false ||
        widget.venue?['isSecret'] == true ||
        widget.venue?['isSecretVenue'] == true ||
        (widget.post['venueMap'] is Map &&
            ((widget.post['venueMap'] as Map)['isSecret'] == true ||
             (widget.post['venueMap'] as Map)['isSecretVenue'] == true ||
             (widget.post['venueMap'] as Map)['showVenueDetails'] == false)) ||
        (widget.post['venue'] is Map &&
            ((widget.post['venue'] as Map)['isSecret'] == true ||
             (widget.post['venue'] as Map)['isSecretVenue'] == true ||
             (widget.post['venue'] as Map)['showVenueDetails'] == false)) ||
        widget.venue?['name']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        widget.post['venue']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        widget.post['venueName']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        (widget.post['venueMap'] is Map &&
            (widget.post['venueMap'] as Map)['name']?.toString().toUpperCase().contains('SECRET VENUE') == true);
    final bool hideVenue = isSecretVenue && !isMyPost && !hasConfirmedBooking;

    final String venueName = hideVenue ? 'SECRET VENUE 🔒' : rawVenueName;

    String content = widget.post['content'] ?? widget.post['message'] ?? '';
    if (hideVenue && rawVenueName.isNotEmpty && rawVenueName != 'Unknown Venue' && !rawVenueName.toUpperCase().contains('SECRET VENUE')) {
      content = content.replaceAll(RegExp(RegExp.escape(rawVenueName), caseSensitive: false), 'a Secret Venue 🔒');
    }
    final String time = widget.post['time'] ?? '';

    final String? photo =
        widget.post['profilePhotoUrl'] ??
        widget.post['profileImageUrl'] ??
        widget.post['photoUrl'] ??
        widget.post['profilePhoto'] ??
        (widget.post['user'] is Map ? widget.post['user']['photoUrl'] : null) ??
        (widget.post['user'] is Map
            ? widget.post['user']['profilePhotoUrl']
            : null) ??
        widget.post['image'];

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(
            context,
            firstName,
            lastName,
            time,
            photo,
            widget.post,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  // Post Content
                  Text(
                    content,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 40),
                  // Venue Context Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.15)),
                      boxShadow: [
                        BoxShadow(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (hideVenue ? Colors.amber : LunaraTheme.electricViolet).withValues(
                                  alpha: 0.1,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                hideVenue ? Icons.lock_outline_rounded : Icons.location_on_rounded,
                                color: hideVenue ? Colors.amber[800] : LunaraTheme.electricViolet,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hideVenue ? 'VENUE PRIVACY' : 'HAPPENING AT',
                                    style: const TextStyle(
                                      color: Colors.black38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    venueName.toUpperCase(),
                                    style: TextStyle(
                                      color: hideVenue ? Colors.amber[900] : Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!hideVenue && widget.venue != null)
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VenueDetailScreen(
                                        venue: widget.venue!,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'VIEW',
                                  style: TextStyle(
                                    color: LunaraTheme.electricViolet,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (hideVenue) ...[
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(left: 44),
                            child: Text(
                              'Locality: ${widget.venue?['area'] ?? widget.venue?['city'] ?? widget.post['area'] ?? widget.post['city'] ?? 'Local Area'} (Exact venue revealed once host approves)',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(left: 44),
                            child: _buildDistanceOrLocationWidget(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Host Details Card
                  const SizedBox(height: 24),
                  const Text(
                    'HOST',
                    style: TextStyle(
                      color: Colors.black38,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      final hostUserMap = widget.post['user'] is Map
                          ? Map<String, dynamic>.from(widget.post['user'])
                          : (widget.post['creator'] is Map
                              ? Map<String, dynamic>.from(widget.post['creator'])
                              : {
                                  'id': widget.post['userId'] ?? widget.post['creatorId'],
                                  'firstName': firstName,
                                  'lastName': lastName,
                                  'photoUrl': photo,
                                  'profilePhotoUrl': photo,
                                  'profileImageUrl': photo,
                                });
                      User? profileUser;
                      try {
                        profileUser = User.fromJson(hostUserMap);
                      } catch (_) {}
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(user: profileUser),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                            backgroundImage: photo != null && photo.trim().isNotEmpty
                                ? NetworkImage(
                                    photo.startsWith('http')
                                        ? photo
                                        : (photo.startsWith('/')
                                            ? '${ApiService.baseUrl}$photo'
                                            : '${ApiService.baseUrl}/$photo'),
                                  )
                                : null,
                            child: photo == null || photo.trim().isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: LunaraTheme.electricViolet,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$firstName $lastName',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Party Plan Host',
                                  style: TextStyle(
                                    color: LunaraTheme.electricViolet.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMyPost
          ? const SizedBox.shrink()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: _isPartyPlanStatusLoading
                    ? Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(LunaraTheme.electricViolet),
                            ),
                          ),
                        ),
                      )
                    : (widget.post['status']?.toString().toLowerCase() == 'inactive' ||
                            widget.post['status']?.toString().toLowerCase() == 'closed' ||
                            widget.post['status']?.toString().toLowerCase() == 'cancelled' ||
                            widget.post['status']?.toString().toLowerCase() == 'completed' ||
                            widget.post['isLive'] == false)
                        ? Container(
                            width: double.infinity,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.lock_rounded, color: Colors.grey),
                                  SizedBox(width: 8),
                                  Text(
                                    'PLAN CLOSED / CONFIRMED WITH ANOTHER USER',
                                    style: TextStyle(
                                      fontFamily: 'AllroundGothic',
                                      color: Colors.grey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : (_isInvitedUser && (_partyPlanRequestStatus == 'pending' || _partyPlanRequestStatus == 'invited' || _partyPlanRequestStatus == null))
                            ? Row(
                                children: [
                                  // Decline Button
                                  Expanded(
                                    flex: 2,
                                    child: SizedBox(
                                      height: 60,
                                      child: OutlinedButton(
                                        onPressed: (_isDecliningInvite || _isAcceptingInvite)
                                            ? null
                                            : _handleRejectPartyPlanInvite,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.redAccent,
                                          side: BorderSide(
                                            color: Colors.redAccent.withValues(alpha: 0.6),
                                            width: 1.5,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                        ),
                                        child: _isDecliningInvite
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.redAccent),
                                                ),
                                              )
                                            : const Text(
                                                'DECLINE',
                                                style: TextStyle(
                                                  fontFamily: 'AllroundGothic',
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Accept Button
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      height: 60,
                                      decoration: BoxDecoration(
                                        gradient: LunaraTheme.purpleGradient,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFb952eb).withValues(alpha: 0.35),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed: (_isAcceptingInvite || _isDecliningInvite)
                                            ? null
                                            : _handleAcceptPartyPlanInvite,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                        ),
                                        child: _isAcceptingInvite
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                                  SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      'ACCEPT INVITE',
                                                      style: TextStyle(
                                                        fontFamily: 'AllroundGothic',
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.bold,
                                                        letterSpacing: 0.5,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : (_partyPlanRequestStatus == 'accepted' || _partyPlanRequestStatus == 'payment_pending')
                                ? Container(
                                    width: double.infinity,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF00C853).withValues(alpha: 0.35),
                                          blurRadius: 16,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PartyPlanDetailScreen(
                                              plan: Map<String, dynamic>.from(widget.post),
                                              autoOpenPaymentSheet: true,
                                            ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.payment_rounded, color: Colors.white, size: 22),
                                          SizedBox(width: 10),
                                          Text(
                                            'PAY SAFETY DEPOSIT (₹99)',
                                            style: TextStyle(
                                              fontFamily: 'AllroundGothic',
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : (_partyPlanRequestStatus == 'confirmed' || _partyPlanRequestStatus == 'paid')
                                    ? Container(
                                        width: double.infinity,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          gradient: LunaraTheme.purpleGradient,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
                                              blurRadius: 16,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PartyPlanDetailScreen(
                                                  plan: Map<String, dynamic>.from(widget.post),
                                                ),
                                              ),
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.celebration_rounded, color: Colors.white, size: 22),
                                              SizedBox(width: 10),
                                              Text(
                                                'JOINED & CONFIRMED 🎉',
                                                style: TextStyle(
                                                  fontFamily: 'AllroundGothic',
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : _alreadyRequested
                                        ? Container(
                                            width: double.infinity,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.green.withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: const FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16.0,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.check_circle_rounded,
                                                      color: Colors.green,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Text(
                                                      'REQUEST SENT — AWAITING HOST APPROVAL',
                                                      style: TextStyle(
                                                        fontFamily: 'AllroundGothic',
                                                        color: Colors.green,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            width: double.infinity,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              gradient: LunaraTheme.purpleGradient,
                                              borderRadius: BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFb952eb).withValues(alpha: 0.35),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: ElevatedButton(
                                              onPressed: (_alreadyRequested || _isProcessing)
                                                  ? null
                                                  : () async {
                                                      if (_alreadyRequested) return;
                                                      final planId = widget.post['id']?.toString() ?? '';
                                                      if (planId.isEmpty) return;

                                                      if (!OptimisticActionGuard.start('JOIN_PARTY_PLAN:$planId')) return;

                                                      final prevAlreadyRequested = _alreadyRequested;

                                                      setState(() {
                                                        _isProcessing = true;
                                                      });

                                                      final messenger = ScaffoldMessenger.of(context);

                                                      try {
                                                        final result = await ApiService.requestToJoinPartyPlanDetailed(planId);
                                                        if (!mounted) return;

                                                        if (result.alreadyRequested || result.success) {
                                                          setState(() {
                                                            _alreadyRequested = true;
                                                            _isProcessing = false;
                                                          });
                                                          if (result.isNewRequest) {
                                                            messenger.showSnackBar(
                                                              SnackBar(
                                                                backgroundColor: Colors.transparent,
                                                                elevation: 0,
                                                                behavior: SnackBarBehavior.floating,
                                                                content: Container(
                                                                  padding: const EdgeInsets.symmetric(
                                                                    horizontal: 20,
                                                                    vertical: 16,
                                                                  ),
                                                                  decoration: BoxDecoration(
                                                                    gradient: LunaraTheme.purpleGradient,
                                                                    borderRadius: BorderRadius.circular(16),
                                                                    boxShadow: [
                                                                      BoxShadow(
                                                                        color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                                                        blurRadius: 15,
                                                                        offset: const Offset(0, 8),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  child: const Row(
                                                                    children: [
                                                                      Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                                                                      SizedBox(width: 12),
                                                                      Expanded(
                                                                        child: Text(
                                                                          'JOIN REQUEST SENT! THE HOST WILL REVIEW IT.',
                                                                          style: TextStyle(
                                                                            color: Colors.white,
                                                                            fontSize: 12,
                                                                            fontWeight: FontWeight.bold,
                                                                            letterSpacing: 0.5,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                        } else {
                                                          if (mounted) {
                                                            setState(() {
                                                              _alreadyRequested = prevAlreadyRequested;
                                                              _isProcessing = false;
                                                            });
                                                          }
                                                          if (TimeLockBlockedDialog.isConflictError(result.message) ||
                                                              (result.rawData != null && result.rawData!['allowed'] == false)) {
                                                            TimeLockBlockedDialog.show(
                                                              context,
                                                              errorData: result.rawData ?? {'message': result.message},
                                                            );
                                                          } else {
                                                            messenger.showSnackBar(
                                                              SnackBar(
                                                                content: Text(TimeLockBlockedDialog.cleanErrorMessage(result.message)),
                                                                backgroundColor: Colors.red,
                                                              ),
                                                            );
                                                          }
                                                        }
                                                      } catch (e) {
                                                        if (mounted) {
                                                          setState(() {
                                                            _alreadyRequested = prevAlreadyRequested;
                                                            _isProcessing = false;
                                                          });
                                                          if (TimeLockBlockedDialog.isConflictError(e)) {
                                                            TimeLockBlockedDialog.showWithMessage(context, e.toString());
                                                          } else {
                                                            messenger.showSnackBar(
                                                              SnackBar(
                                                                content: Text(TimeLockBlockedDialog.cleanErrorMessage(e)),
                                                                backgroundColor: Colors.red,
                                                              ),
                                                            );
                                                          }
                                                        }
                                                      } finally {
                                                        OptimisticActionGuard.end('JOIN_PARTY_PLAN:$planId');
                                                      }
                                                    },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    _isProcessing
                                                        ? const SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child: CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                            ),
                                                          )
                                                        : Icon(hideVenue ? Icons.lock_rounded : Icons.bolt, color: Colors.white),
                                                    const SizedBox(width: 12),
                                                    Flexible(
                                                      child: Text(
                                                        _isProcessing
                                                            ? 'SENDING REQUEST...'
                                                            : (hideVenue
                                                                ? 'SEND REQUEST TO SEE VENUE & DETAILS'
                                                                : 'JOIN THE VIBE'),
                                                        textAlign: TextAlign.center,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontFamily: 'AllroundGothic',
                                                          color: Colors.white,
                                                          fontSize: hideVenue ? 13 : 16,
                                                          fontWeight: FontWeight.bold,
                                                          letterSpacing: 1,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
              ),
            ),
    );
  }

  // ─── Shared Sliver App Bar ─────────────────────────────────────────────────
  Widget _buildSliverAppBar(
    BuildContext context,
    String firstName,
    String lastName,
    String time,
    String? photo,
    Map<String, dynamic> post,
  ) {
    final bool isMyPost =
        post['userId']?.toString() == ApiService.currentUserId ||
        (post['user'] != null &&
            post['user']['id']?.toString() == ApiService.currentUserId);
    final bool hasConfirmedBooking = post['canSeeVenue'] == true ||
        post['hasConfirmedBooking'] == true ||
        post['isMatched'] == true ||
        _alreadyRequested && (_meetRequest?.joiners != null);
    final bool isSecretVenue = post['showVenueDetails'] == false ||
        post['isSecret'] == true ||
        post['isSecretVenue'] == true ||
        widget.venue?['showVenueDetails'] == false ||
        widget.venue?['isSecret'] == true ||
        widget.venue?['isSecretVenue'] == true ||
        (post['venueMap'] is Map &&
            ((post['venueMap'] as Map)['isSecret'] == true ||
             (post['venueMap'] as Map)['isSecretVenue'] == true ||
             (post['venueMap'] as Map)['showVenueDetails'] == false)) ||
        (post['venue'] is Map &&
            ((post['venue'] as Map)['isSecret'] == true ||
             (post['venue'] as Map)['isSecretVenue'] == true ||
             (post['venue'] as Map)['showVenueDetails'] == false)) ||
        widget.venue?['name']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        post['venue']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        post['venueName']?.toString().toUpperCase().contains('SECRET VENUE') == true ||
        (post['venueMap'] is Map &&
            (post['venueMap'] as Map)['name']?.toString().toUpperCase().contains('SECRET VENUE') == true);
    final bool hideVenue = isSecretVenue && !isMyPost && !hasConfirmedBooking;

    // Determine venue/banner photo (prefer venue or event banner image, avoid host profile photo taking over full banner)
    String? bannerPhoto;
    if (!hideVenue) {
      final venueMap =
          widget.venue ??
          (post['venue'] is Map ? post['venue'] as Map<String, dynamic> : null);
      if (venueMap != null) {
        if (venueMap['images'] is List &&
            (venueMap['images'] as List).isNotEmpty) {
          final firstImg = (venueMap['images'] as List).first;
          if (firstImg is Map) {
            final u =
                firstImg['url'] ?? firstImg['imageUrl'] ?? firstImg['filePath'];
            if (u != null && u.toString().isNotEmpty) bannerPhoto = u.toString();
          } else if (firstImg is String && firstImg.isNotEmpty) {
            bannerPhoto = firstImg;
          }
        }
        bannerPhoto ??=
            venueMap['imageUrl']?.toString() ??
            venueMap['coverImage']?.toString() ??
            venueMap['photoUrl']?.toString();
      }
      bannerPhoto ??=
          post['venueImage']?.toString() ??
          post['bannerUrl']?.toString() ??
          post['bannerImage']?.toString();

      if (bannerPhoto != null &&
          bannerPhoto.startsWith('/') &&
          !bannerPhoto.startsWith('assets')) {
        bannerPhoto = '${ApiService.baseUrl}$bannerPhoto';
      }
    }

    // Host photo for profile chip
    String? hostPhoto = photo;
    if (hostPhoto != null &&
        hostPhoto.startsWith('/') &&
        !hostPhoto.startsWith('assets')) {
      hostPhoto = '${ApiService.baseUrl}$hostPhoto';
    }

    // Determine Event Title
    final String rawVenueName = widget.venue?['name']?.toString() ??
        (post['venue'] is Map ? post['venue']['name']?.toString() : null) ??
        (post['venue'] is String ? post['venue']?.toString() : null) ??
        (post['venueMap'] is Map ? post['venueMap']['name']?.toString() : null) ??
        post['venueName']?.toString() ??
        '';
    String rawSubject =
        (post['subject'] ??
                post['title'] ??
                post['message'] ??
                (hideVenue ? 'SECRET VENUE' : rawVenueName) ??
                'STRANGERS MEET')
            .toString()
            .trim();
    if (rawSubject.toUpperCase().contains('DEPOSIT PENDING') || rawSubject.toUpperCase().contains('ACTION REQUIRED')) {
      rawSubject = post['tagline'] ?? post['plan']?['subject'] ?? 'STRANGERS MEET';
    }
    String displayTitle = rawSubject.isNotEmpty
        ? rawSubject.toUpperCase()
        : 'STRANGERS MEET';

    if (hideVenue) {
      if (rawVenueName.isNotEmpty && !rawVenueName.toUpperCase().contains('SECRET VENUE')) {
        displayTitle = displayTitle.replaceAll(RegExp(RegExp.escape(rawVenueName.toUpperCase())), 'SECRET VENUE 🔒');
      }
      if (displayTitle.isEmpty || displayTitle == rawVenueName.toUpperCase()) {
        displayTitle = 'SECRET VENUE 🔒';
      }
    }

    final bool isVerified =
        post['isVerified'] == true || post['verified'] == true;

    User? profileUser;
    try {
      profileUser = User.fromJson(post['user'] ?? post);
    } catch (_) {}

    return SliverAppBar(
      expandedHeight: 340,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            child: IconButton(
              icon: const Icon(Icons.person_rounded, color: Colors.white),
              tooltip: 'Host Profile',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(user: profileUser),
                  ),
                );
              },
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (hideVenue)
              Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/secretimag.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2D0060), Color(0xFF0D001C)],
                        ),
                      ),
                    ),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.45)),
                ],
              ),
            if (hideVenue)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.5), width: 2),
                      ),
                      child: const Icon(Icons.lock_rounded, color: Colors.white, size: 44),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SECRET VENUE 🔒',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Photo & exact location revealed upon host approval',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              LunaraNetworkImage(imageUrl: bannerPhoto, fit: BoxFit.cover),

            // Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),

            // Event Details & Host Pill
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            fontFamily: 'AllroundGothic',
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 6),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Date & Time Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: LunaraTheme.electricViolet,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: LunaraTheme.electricViolet.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_filled_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              time,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Hosted by Host Chip
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(user: profileUser),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.white24,
                                backgroundImage:
                                    hostPhoto != null && hostPhoto.isNotEmpty
                                    ? NetworkImage(hostPhoto)
                                    : null,
                                child: hostPhoto == null || hostPhoto.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        size: 12,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Hosted by $firstName $lastName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified_rounded,
                                  color: Color(0xFF2196F3),
                                  size: 14,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
