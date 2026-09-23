// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/smart_checkout_sheet.dart';
import 'chat_screen.dart';
import 'party_plan_ticket_screen.dart';
import '../discovery/digital_ticket_screen.dart';
import 'plan_hub_screen.dart';
import '../../widgets/top_notification_banner.dart';
import '../../widgets/dialogs/time_lock_blocked_dialog.dart';
import '../../services/optimistic_action_guard.dart';
import '../../services/realtime_sync_manager.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../widgets/lunara_cached_image.dart';

class _VenueImageFallback extends StatelessWidget {
  const _VenueImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D0060), Color(0xFF0D001C)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.nightlife_rounded, color: Colors.white24, size: 72),
      ),
    );
  }
}

class _SecretVenueImagePlaceholder extends StatelessWidget {
  const _SecretVenueImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/secretimag.png',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D0060), Color(0xFF0D001C)],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: Colors.white.withValues(alpha: 0.7), size: 56),
                const SizedBox(height: 8),
                Text(
                  'SECRET VENUE 🔒',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PartyPlanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> plan;
  final bool autoOpenPaymentSheet;

  const PartyPlanDetailScreen({
    super.key,
    required this.plan,
    this.autoOpenPaymentSheet = false,
  });

  @override
  State<PartyPlanDetailScreen> createState() => _PartyPlanDetailScreenState();
}

class _PartyPlanDetailScreenState extends State<PartyPlanDetailScreen> {
  bool _isJoining = false;
  bool _alreadyRequested = false;
  bool _isInvitedUser = false;
  bool _isAcceptingInvite = false;
  bool _isDecliningInvite = false;
  bool _isStatusLoading = true;
  String? _requestStatus;
  String? _activeRequestId;
  String? _fetchedVenueImageUrl;
  Map<String, dynamic>? _cancellationRequest;
  bool _isWindowClosed = false;
  bool _isLoadingCancellation = false;
  String? _currentUserId;
  List<Map<String, dynamic>> _pendingRequests = [];
  final Set<String> _processingReqIds = {};

  @override
  void initState() {
    super.initState();
    final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    final currentUid = ApiService.currentUserId ?? '';
    final syncRequested = ApiService.isPartyPlanRequestedSync(targetPlanId);
    final syncReqData = ApiService.getCachedPartyPlanRequestSync(targetPlanId);

    // Extract any existing request data passed directly in widget.plan
    Map<String, dynamic>? embeddedReq;
    if (widget.plan['myRequest'] is Map) {
      embeddedReq = Map<String, dynamic>.from(widget.plan['myRequest']);
    } else if (widget.plan['acceptedJoinerRequest'] is Map) {
      final reqMap = Map<String, dynamic>.from(widget.plan['acceptedJoinerRequest']);
      final reqId = (reqMap['requesterId'] ?? reqMap['requester']?['id'] ?? '').toString();
      if (currentUid.isEmpty || reqId.isEmpty || reqId == currentUid) {
        embeddedReq = reqMap;
      }
    } else if (widget.plan['requests'] is List) {
      for (final r in widget.plan['requests']) {
        if (r is Map) {
          final reqId = (r['requesterId'] ?? r['requester']?['id'] ?? r['userId'] ?? '').toString();
          if (currentUid.isNotEmpty && reqId == currentUid) {
            embeddedReq = Map<String, dynamic>.from(r);
            break;
          }
        }
      }
    }

    // Extract cancellation request if already present
    final rawCancelReq = widget.plan['cancellationRequest'] ?? widget.plan['activeCancellationRequest'];
    if (rawCancelReq is Map) {
      _cancellationRequest = Map<String, dynamic>.from(rawCancelReq);
    }

    final bool isPartnerByPlan = _isPartnerPlan(widget.plan);
    final effectiveReqData = syncReqData ?? embeddedReq;
    final syncRawStatus = (effectiveReqData?['status'] ?? (isPartnerByPlan ? 'payment_pending' : 'pending'))?.toString().toLowerCase();
    final syncJoinerPaid = _isJoinerPaid(widget.plan, effectiveReqData);
    final bool hasInitialCancel = (_cancellationRequest != null && (_cancellationRequest!['status'] == 'pending' || _cancellationRequest!['status'] == 'approved')) ||
        ((widget.plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'pending');
    String? initialReqStatus = (syncJoinerPaid || hasInitialCancel) ? 'confirmed' : (syncRawStatus == 'accepted' ? 'payment_pending' : syncRawStatus);
    bool initialRequested = syncRequested || isPartnerByPlan || embeddedReq != null || hasInitialCancel;
    if (initialReqStatus == 'cancelled' || initialReqStatus == 'rejected' || initialReqStatus == 'declined' || initialReqStatus == 'payment_failed') {
      if (!isPartnerByPlan && !hasInitialCancel) {
        initialRequested = false;
        ApiService.markPartyPlanAsCancelledLocal(targetPlanId);
      }
    }

    _alreadyRequested = (widget.plan['hasRequested'] == true || initialRequested || hasInitialCancel) &&
        (isPartnerByPlan || hasInitialCancel || (initialReqStatus != 'payment_failed' && initialReqStatus != 'cancelled'));
    if (effectiveReqData != null || isPartnerByPlan || hasInitialCancel) {
      _activeRequestId = effectiveReqData?['id']?.toString() ??
          effectiveReqData?['requestId']?.toString() ??
          widget.plan['requestId']?.toString() ??
          widget.plan['activeRequestId']?.toString() ??
          widget.plan['matchedRequestId']?.toString();
      _requestStatus = initialReqStatus;
    }

    final initialReqs = widget.plan['pendingIncomingRequests'] ?? widget.plan['requests'];
    if (initialReqs is List) {
      _pendingRequests = initialReqs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }

    final selectedUsers = widget.plan['selectedUsers'] ?? widget.plan['selectedUserIds'];
    final bool inSelectedUsers = selectedUsers is List && selectedUsers.any((u) => u?.toString() == currentUid);
    final hostId = (widget.plan['userId'] ?? widget.plan['hostId'] ?? widget.plan['user']?['id'] ?? '').toString();

    if (widget.plan['isInvite'] == true ||
        widget.plan['isInvitedUser'] == true ||
        widget.plan['type'] == 'party_plan_invitation' ||
        widget.plan['eventType'] == 'party_plan_invitation' ||
        widget.plan['requestType'] == 'private_invite' ||
        (currentUid.isNotEmpty && currentUid != hostId && inSelectedUsers)) {
      _isInvitedUser = true;
    }
    if (widget.plan['requestId'] != null || widget.plan['activeRequestId'] != null) {
      final rStatus = (widget.plan['status'] ?? widget.plan['requestStatus'] ?? '').toString().toLowerCase();
      if (rStatus != 'cancelled' && rStatus != 'payment_failed' && rStatus != 'rejected') {
        _activeRequestId = (widget.plan['requestId'] ?? widget.plan['activeRequestId']).toString();
        _alreadyRequested = true;
      }
    }
    _initializeScreenData();
    _initListeners();

    if (widget.autoOpenPaymentSheet && !_isHostPlan(widget.plan) && !_isJoinerPaid(widget.plan)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isHostPlan(widget.plan) && !_isJoinerPaid(widget.plan)) {
          _openDepositPaymentSheet();
        }
      });
    }
  }

  @override
  void dispose() {
    _disposeListeners();
    super.dispose();
  }

  void _initListeners() {
    ApiService.planPostedNotifier.addListener(_onPlanChanged);
    RealtimeSyncManager.instance.partyPlanNotifier.addListener(_onPlanChanged);
    RealtimeSyncManager.instance.liveFeedNotifier.addListener(_onPlanChanged);
    RealtimeSyncManager.instance.globalSyncTick.addListener(_onPlanChanged);

    ApiService.addSocketListener('party_plan_created', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_created', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_received', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_updated', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_cancelled', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_rejected', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_request_accepted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_host_paid', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_joiner_paid', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_deleted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_cancelled', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_cancellation_requested', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_cancellation_declined', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_relisted', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_updated', _onSocketUpdate);
    ApiService.addSocketListener('live_feed_update', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_partner_selected', _onSocketUpdate);
    ApiService.addSocketListener('plan_unavailable', _onSocketUpdate);
    ApiService.addSocketListener('notification_created', _onSocketUpdate);
  }

  void _disposeListeners() {
    ApiService.planPostedNotifier.removeListener(_onPlanChanged);
    RealtimeSyncManager.instance.partyPlanNotifier.removeListener(_onPlanChanged);
    RealtimeSyncManager.instance.liveFeedNotifier.removeListener(_onPlanChanged);
    RealtimeSyncManager.instance.globalSyncTick.removeListener(_onPlanChanged);

    ApiService.removeSocketListener('party_plan_created', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_created', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_received', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_updated', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_cancelled', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_rejected', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_request_accepted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_host_paid', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_joiner_paid', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_deleted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_cancelled', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_cancellation_requested', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_cancellation_declined', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_relisted', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_updated', _onSocketUpdate);
    ApiService.removeSocketListener('live_feed_update', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_partner_selected', _onSocketUpdate);
    ApiService.removeSocketListener('plan_unavailable', _onSocketUpdate);
    ApiService.removeSocketListener('notification_created', _onSocketUpdate);
  }

  void _onPlanChanged() {
    if (!mounted) return;
    _refreshPlanDetails();
    _fetchRequestsIfNeeded();
    _checkRequestStatus();
  }

  void _onSocketUpdate(dynamic data) {
    if (!mounted) return;
    _refreshPlanDetails();
    _fetchRequestsIfNeeded();
    _checkRequestStatus();
  }

  Future<void> _fetchRequestsIfNeeded() async {
    if (!_isHostPlan(widget.plan)) return;
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) return;

    try {
      final res = await ApiService.get('/api/mobile/party-plans/$planId/requests');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['success'] == true && data['data'] is List) {
          if (mounted) {
            setState(() {
              _pendingRequests = (data['data'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending')
                  .toList();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching party plan requests: $e');
    }
  }

  Future<void> _handleAcceptPartyPlanRequest(String reqId) async {
    if (_processingReqIds.contains(reqId)) return;
    if (!OptimisticActionGuard.start('ACCEPT_PARTY_REQ:$reqId')) return;

    setState(() => _processingReqIds.add(reqId));

    // Optimistic UI: update status in place to keep the profile visible with status badge
    final prevPending = List<Map<String, dynamic>>.from(_pendingRequests);
    final reqIndex = _pendingRequests.indexWhere((r) => (r['id'] ?? r['requestId'])?.toString() == reqId);
    if (reqIndex != -1) {
      setState(() {
        _pendingRequests[reqIndex] = {
          ..._pendingRequests[reqIndex],
          'status': 'ACCEPTED',
          'lifecycleStatus': 'USER_ACCEPTED',
        };
      });
    }

    try {
      final res = await ApiService.acceptPartyPlanRequest(reqId);
      if (res != null) {
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        ApiService.planPostedNotifier.value++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request accepted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _refreshPlanDetails();
        }
      } else {
        // Rollback
        if (mounted) {
          setState(() {
            _pendingRequests = prevPending;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to accept request.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingRequests = prevPending;
        });
        debugPrint('Error accepting request: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      OptimisticActionGuard.end('ACCEPT_PARTY_REQ:$reqId');
      if (mounted) setState(() => _processingReqIds.remove(reqId));
    }
  }

  Future<void> _handleRejectPartyPlanRequest(String reqId) async {
    if (_processingReqIds.contains(reqId)) return;
    if (!OptimisticActionGuard.start('REJECT_PARTY_REQ:$reqId')) return;

    setState(() => _processingReqIds.add(reqId));

    // Optimistic UI: update status in place to keep the profile visible with status badge
    final prevPending = List<Map<String, dynamic>>.from(_pendingRequests);
    final reqIndex = _pendingRequests.indexWhere((r) => (r['id'] ?? r['requestId'])?.toString() == reqId);
    if (reqIndex != -1) {
      setState(() {
        _pendingRequests[reqIndex] = {
          ..._pendingRequests[reqIndex],
          'status': 'REJECTED',
          'lifecycleStatus': 'REJECTED',
        };
      });
    }

    try {
      final success = await ApiService.rejectPartyPlanRequest(reqId);
      if (success) {
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        ApiService.planPostedNotifier.value++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request declined.'),
              backgroundColor: Colors.grey,
            ),
          );
          _refreshPlanDetails();
        }
      } else {
        // Rollback
        if (mounted) {
          setState(() {
            _pendingRequests = prevPending;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to decline request.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingRequests = prevPending;
        });
        debugPrint('Error declining request: $e');
      }
    } finally {
      OptimisticActionGuard.end('REJECT_PARTY_REQ:$reqId');
      if (mounted) setState(() => _processingReqIds.remove(reqId));
    }
  }

  Future<void> _handleCancelPrivateRequest(String reqId) async {
    if (_processingReqIds.contains(reqId)) return;
    if (!OptimisticActionGuard.start('CANCEL_PARTY_REQ:$reqId')) return;

    setState(() => _processingReqIds.add(reqId));

    final prevPending = List<Map<String, dynamic>>.from(_pendingRequests);
    final reqIndex = _pendingRequests.indexWhere((r) => (r['id'] ?? r['requestId'])?.toString() == reqId);
    if (reqIndex != -1) {
      setState(() {
        _pendingRequests[reqIndex] = {
          ..._pendingRequests[reqIndex],
          'status': 'CANCELLED',
          'lifecycleStatus': 'CANCELLED',
        };
      });
    }

    try {
      bool success = await ApiService.cancelPartyPlanRequest(reqId);
      if (!success) {
        success = await ApiService.rejectPartyPlanRequest(reqId);
      }
      if (success) {
        ApiService.clearBookingCache();
        ApiService.notifyFeedNeedsRefresh();
        ApiService.planPostedNotifier.value++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Private invitation cancelled.'),
              backgroundColor: Colors.grey,
            ),
          );
          _refreshPlanDetails();
        }
      } else {
        if (mounted) {
          setState(() {
            _pendingRequests = prevPending;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to cancel invitation.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingRequests = prevPending;
        });
        debugPrint('Error cancelling invitation: $e');
      }
    } finally {
      OptimisticActionGuard.end('CANCEL_PARTY_REQ:$reqId');
      if (mounted) setState(() => _processingReqIds.remove(reqId));
    }
  }

  Future<void> _initializeScreenData() async {
    final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (targetPlanId.isEmpty) {
      if (mounted) setState(() => _isStatusLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        ApiService.getCurrentUserId(),
        ApiService.fetchPartyPlanDetail(targetPlanId),
        ApiService.getPartyPlanCancellationRequest(targetPlanId),
        ApiService.fetchMyPartyPlanRequests(),
      ]);

      if (!mounted) return;

      final uid = results[0] as String?;
      final freshPlan = results[1] as Map<String, dynamic>?;
      final cancelRes = results[2] as Map<String, dynamic>?;
      final myRequests = results[3] as List<dynamic>? ?? [];

      if (freshPlan != null) {
        widget.plan.addAll(freshPlan);
        widget.plan['planId'] = targetPlanId;
      }

      final currentUid = uid ?? ApiService.currentUserId ?? '';
      _currentUserId = currentUid;

      if (cancelRes != null) {
        if (cancelRes['isWindowClosed'] == true) {
          _isWindowClosed = true;
        }
        final cancelReq = cancelRes['cancellationRequest'];
        _cancellationRequest = cancelReq is Map<String, dynamic>
            ? cancelReq
            : (cancelReq is Map ? Map<String, dynamic>.from(cancelReq) : null);
      } else {
        final rawCancelReq = widget.plan['cancellationRequest'] ?? widget.plan['activeCancellationRequest'];
        if (rawCancelReq is Map) {
          _cancellationRequest = Map<String, dynamic>.from(rawCancelReq);
        }
      }

      final rawDateTime = widget.plan['planDateTime'] ??
          widget.plan['eventDateTime'] ??
          widget.plan['planDate'] ??
          widget.plan['partyDate'] ??
          widget.plan['bookingDate'];
      if (rawDateTime != null) {
        try {
          final eventTime = DateTime.parse(rawDateTime.toString()).toLocal();
          final diff = eventTime.difference(DateTime.now());
          if (diff.inMinutes < 180) {
            _isWindowClosed = true;
          }
        } catch (_) {}
      }

      final bool isHost = _isHostPlan(widget.plan);
      if (isHost) {
        try {
          final res = await ApiService.get('/api/mobile/party-plans/$targetPlanId/requests');
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data is Map && data['success'] == true && data['data'] is List) {
              _pendingRequests = (data['data'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending')
                  .toList();
            }
          }
        } catch (e) {
          debugPrint('Error fetching incoming requests for host: $e');
        }
      } else {
        final bool isPartnerByPlan = _isPartnerPlan(widget.plan);
        final bool isPaidInitial = _isJoinerPaid(widget.plan);

        bool requested = isPartnerByPlan || _alreadyRequested;
        bool isInvited = _isInvitedUser;
        String? reqStatus = (isPartnerByPlan && isPaidInitial) ? 'confirmed' : (_requestStatus ?? 'payment_pending');
        String? reqId = _activeRequestId ??
            widget.plan['requestId']?.toString() ??
            widget.plan['activeRequestId']?.toString() ??
            widget.plan['matchedRequestId']?.toString();
        bool foundInFreshList = false;

        if (widget.plan['requests'] is List) {
          for (final r in widget.plan['requests']) {
            if (r is Map) {
              final requesterId = (r['requesterId'] ?? r['requester']?['id'] ?? r['userId'] ?? '').toString();
              if (currentUid.isNotEmpty && requesterId == currentUid) {
                foundInFreshList = true;
                reqId = r['id']?.toString() ?? reqId;
                final rawStatus = (r['status'] ?? 'pending').toString().toLowerCase();
                final joinerPaid = _isJoinerPaid(widget.plan, Map<String, dynamic>.from(r));
                reqStatus = joinerPaid ? 'confirmed' : (rawStatus == 'accepted' ? 'payment_pending' : rawStatus);
                if (rawStatus != 'cancelled' && rawStatus != 'rejected' && rawStatus != 'declined') {
                  requested = true;
                }
                break;
              }
            }
          }
        }

        for (final req in myRequests) {
          if (req is! Map) continue;
          final planId = req['partyPlanId']?.toString() ?? req['planId']?.toString() ?? req['plan']?['id']?.toString();
          if (planId == targetPlanId) {
            foundInFreshList = true;
            reqId = req['id']?.toString() ?? reqId;
            final rawStatus = (req['status'] ?? 'pending').toString().toLowerCase();
            final joinerPaid = _isJoinerPaid(widget.plan, Map<String, dynamic>.from(req));
            reqStatus = joinerPaid ? 'confirmed' : (rawStatus == 'accepted' ? 'payment_pending' : rawStatus);

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

            if (rawStatus != 'cancelled' &&
                rawStatus != 'rejected' &&
                rawStatus != 'declined' &&
                rawStatus != 'payment_failed' &&
                !isPaymentExpired) {
              requested = true;
            } else if (!isPartnerByPlan) {
              requested = false;
              reqId = null;
              reqStatus = isPaymentExpired ? 'payment_failed' : rawStatus;
            }

            final reqIsInvite = req['isInvite'] == true ||
                req['requestType'] == 'private_invite' ||
                req['isPrivateInvite'] == true ||
                req['invitedBy'] != null ||
                req['type'] == 'party_plan_invitation' ||
                req['type'] == 'invitation';
            if (reqIsInvite) {
              isInvited = true;
            }
            break;
          }
        }

        if (isPartnerByPlan) {
          requested = true;
          reqStatus = (isPaidInitial || _isJoinerPaid(widget.plan)) ? 'confirmed' : 'payment_pending';
        } else if (!foundInFreshList && _activeRequestId != null && _alreadyRequested) {
          requested = true;
          reqStatus = _requestStatus;
          reqId = _activeRequestId;
        }

        final hostId = (widget.plan['userId'] ?? widget.plan['hostId'] ?? widget.plan['user']?['id'] ?? '').toString();
        final selectedUsers = widget.plan['selectedUsers'] ?? widget.plan['selectedUserIds'];
        final bool inSelectedUsers = selectedUsers is List && selectedUsers.any((u) => u?.toString() == currentUid);
        if (currentUid.isNotEmpty && currentUid != hostId && (inSelectedUsers || widget.plan['isInvite'] == true || widget.plan['requestType'] == 'private_invite')) {
          isInvited = true;
        }

        if (isInvited && reqId == null) {
          reqId = targetPlanId;
        }

        _alreadyRequested = requested;
        _isInvitedUser = isInvited;
        _activeRequestId = reqId ?? _activeRequestId;
        _requestStatus = reqStatus ?? (_isInvitedUser ? 'pending' : null);
      }

      final freshImg = _getVenueImageUrl();
      if (freshImg != null && freshImg.isNotEmpty) {
        _fetchedVenueImageUrl = freshImg;
      }

      if (mounted) {
        setState(() {
          _isStatusLoading = false;
        });
      }
      _loadVenueDetailsIfNeeded();
    } catch (e) {
      debugPrint('Error in _initializeScreenData: $e');
      if (mounted) {
        setState(() {
          _isStatusLoading = false;
        });
      }
    }
  }

  Future<void> _refreshPlanDetails() async {
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) return;

    final plan = await ApiService.fetchPartyPlanDetail(planId);
    if (!mounted || plan == null) return;
    setState(() {
      widget.plan.addAll(plan);
      widget.plan['planId'] = planId;
      final freshImg = _getVenueImageUrl();
      if (freshImg != null && freshImg.isNotEmpty) {
        _fetchedVenueImageUrl = freshImg;
      }
      if (plan['requests'] is List) {
        _pendingRequests = (plan['requests'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending')
            .toList();
      }
    });
    _checkRequestStatus();
    _loadVenueDetailsIfNeeded();
    _fetchCurrentUserAndCancellationState();
    _fetchRequestsIfNeeded();
  }

  Future<void> _fetchCurrentUserAndCancellationState() async {
    try {
      final uid = await ApiService.getCurrentUserId();
      final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
      
      final rawDateTime = widget.plan['planDateTime'] ??
          widget.plan['eventDateTime'] ??
          widget.plan['planDate'] ??
          widget.plan['partyDate'] ??
          widget.plan['bookingDate'];
      if (rawDateTime != null) {
        try {
          final eventTime = DateTime.parse(rawDateTime.toString()).toLocal();
          final diff = eventTime.difference(DateTime.now());
          if (diff.inMinutes < 180) {
            if (mounted) setState(() => _isWindowClosed = true);
          }
        } catch (_) {}
      }

      if (targetPlanId.isNotEmpty) {
        final res = await ApiService.getPartyPlanCancellationRequest(targetPlanId);
        if (mounted) {
          final cancelReq = res?['cancellationRequest'];
          setState(() {
            _currentUserId = uid;
            if (res?['isWindowClosed'] == true) _isWindowClosed = true;
            _cancellationRequest = cancelReq is Map<String, dynamic>
                ? cancelReq
                : (cancelReq is Map ? Map<String, dynamic>.from(cancelReq) : null);
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching cancellation state: $e');
    }
  }

  bool _isPlanFullyConfirmed() {
    final plan = widget.plan;
    final bool isHost = _isHostPlan(plan);
    final String pLife = (plan['lifecycleStatus'] ?? plan['lifecycle_status'] ?? '').toString().toLowerCase();
    final String pStatus = (plan['status'] ?? '').toString().toLowerCase();
    final bool joinerPaid = _isJoinerPaid(plan);
    final bool isPartner = _isPartnerPlan(plan);
    final bool hasPendingCancel = (_cancellationRequest != null &&
            (_cancellationRequest!['status'] == 'pending' || _cancellationRequest!['status'] == 'approved')) ||
        ((plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'pending') ||
        (plan['cancellationRequest'] != null &&
            ((plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'pending' ||
                (plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'approved'));

    if (hasPendingCancel) return true;
    if (plan['hasConfirmedBooking'] == true || plan['isConfirmed'] == true || plan['matchConfirmed'] == true) return true;
    if (pLife == 'match_confirmed' ||
        pLife == 'chat_enabled' ||
        pLife == 'arrival_confirmation' ||
        pLife == 'both_arrived' ||
        pLife == 'event_reminder' ||
        pLife == 'plan_completed') {
      return true;
    }
    if (pStatus == 'matched' || pStatus == 'confirmed') return true;

    final String hostPay = (plan['hostPaymentStatus'] ?? plan['host_payment_status'] ?? '').toString().toLowerCase();
    final bool isHostPaid = hostPay == 'paid' || hostPay == 'completed' || (plan['paymentStatus'] ?? '').toString().toLowerCase() == 'confirmed';
    final bool isHostPaysOnly = (plan['paymentType'] ?? plan['payment_type'] ?? '').toString().toLowerCase() == 'host_pays' ||
        (plan['paymentType'] ?? plan['payment_type'] ?? '').toString().toLowerCase() == 'i_pay' ||
        (plan['paymentType'] ?? plan['payment_type'] ?? '').toString().toLowerCase() == 'free';

    if (isHost) {
      if (isHostPaid && (joinerPaid || isHostPaysOnly) && (plan['matchedPartner'] != null || plan['partner'] != null || plan['acceptedJoinerRequest'] != null || plan['partnerId'] != null || plan['matchedUserId'] != null || plan['matchedRequestId'] != null)) {
        return true;
      }
    } else {
      if ((isPartner && joinerPaid) || _requestStatus == 'confirmed' || _requestStatus == 'paid') {
        return true;
      }
    }

    return false;
  }

  void _showCancellationStep1Dialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('CANCEL THIS PLAN?', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action will notify the other participant. Both participants must confirm the cancellation before the Party Plan is cancelled.',
              style: TextStyle(color: Color(0xFF334155), fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Frequent cancellations may affect your Commitment Deposit / Reliability Score.',
              style: TextStyle(color: Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
            ),
            SizedBox(height: 14),
            const Text('If approved:', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Text('• Commitment Deposit (${_getEffectiveRefundText()}) will be returned to both users\' Lunara Wallets.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            SizedBox(height: 4),
            Text('• Chat will become read-only (archived after 24h).', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            SizedBox(height: 4),
            Text('• Reliability Score may decrease for initiator (-5 pts).', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('KEEP PLAN', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCancellationStep2ReasonModal();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('REQUEST CANCELLATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  void _showCancellationStep2ReasonModal() {
    String selectedReason = 'my_plans_changed';
    final TextEditingController otherController = TextEditingController();

    final Map<String, String> reasonOptions = {
      'my_plans_changed': 'My plans have changed',
      'not_available': 'I\'m not available anymore',
      'not_interested': 'Not interested anymore',
      'found_another_plan': 'Found another plan',
      'venue_changed': 'Venue changed',
      'personal_reasons': 'Personal reasons',
      'other': 'Other',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 16),
                    const Text('Why are you cancelling?', style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('Select a reason for internal record. This is never displayed publicly.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    const SizedBox(height: 16),
                    ...reasonOptions.entries.map((entry) {
                      final isSelected = selectedReason == entry.key;
                      return InkWell(
                        onTap: () => setModalState(() => selectedReason = entry.key),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.redAccent.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? Colors.redAccent : const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? Colors.redAccent : const Color(0xFF94A3B8),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(entry.value, style: TextStyle(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569), fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (selectedReason == 'other') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: otherController,
                        maxLength: 150,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter reason (max 150 characters)',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoadingCancellation
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                final otherText = selectedReason == 'other' ? otherController.text.trim() : null;
                                final bool isHost = _isHostPlan(widget.plan);
                                final bool isPlanConfirmed = _isPlanFullyConfirmed();
                                if (isHost && !isPlanConfirmed) {
                                  _showHostCancellationChoiceDialog(selectedReason, otherText);
                                } else {
                                  await _submitCancellationRequest(selectedReason, otherText);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('PROCEED WITH CANCELLATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
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

  void _showHostCancellationChoiceDialog(String selectedReason, String? otherText) {
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    final venue = _extractVenue(widget.plan);
    final venueName = venue['name'] as String? ?? (widget.plan['venue'] is String ? widget.plan['venue'] as String : 'the venue');
    final vis = widget.plan['visibility']?.toString().toLowerCase() ?? 'public';
    final isPrivateOrBoth = vis == 'private' || vis == 'both';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: LunaraTheme.electricViolet, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cancel Party Plan',
                style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select an action for your Party Plan at $venueName:',
              style: const TextStyle(color: Color(0xFF334155), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 18),
                      SizedBox(width: 8),
                      Text('Option A: Cancel & Refund', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Party Plan permanently ends.\n• ${_getEffectiveRefundText()} Commitment Deposit refunded to your Lunara Wallet.\n• All pending requests are cancelled.',
                    style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11.5, height: 1.3),
                  ),
                ],
              ),
            ),
            if (isPrivateOrBoth) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.public_rounded, color: Color(0xFF059669), size: 18),
                        SizedBox(width: 8),
                        Text('Option B: Repost Publicly', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Makes your plan public in the Live Feed.\n• Anyone nearby can discover and join.\n• Your ${_getEffectiveRefundText()} deposit remains active.',
                      style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11.5, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_repeat_rounded, color: LunaraTheme.electricViolet, size: 18),
                      const SizedBox(width: 8),
                      Text(isPrivateOrBoth ? 'Option C: Reschedule' : 'Option B: Repost Plan', style: const TextStyle(color: LunaraTheme.electricViolet, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Reschedule for a new date & time.\n• Remains active & live in feed (no refund).\n• Prior requests cleared for new schedule.',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 11.5, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('KEEP PLAN', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleHostCancelAndRefund(planId, selectedReason, otherText);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('CANCEL & REFUND', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          if (isPrivateOrBoth)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _handleHostMakePublic(planId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('REPOST PUBLICLY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleHostRepostFlow(planId, selectedReason, otherText);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isPrivateOrBoth ? 'RESCHEDULE' : 'REPOST PLAN', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleHostMakePublic(String planId) async {
    setState(() => _isLoadingCancellation = true);
    final res = await ApiService.makePartyPlanPublic(planId);
    if (!mounted) return;
    setState(() {
      _isLoadingCancellation = false;
      if (res?['success'] == true) {
        widget.plan['visibility'] = 'public';
        widget.plan['isLive'] = true;
      }
    });

    if (res?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Plan is now Public in the Live Feed! Anyone can now discover and join.'),
          backgroundColor: Colors.green,
        ),
      );
      _checkRequestStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res?['message'] ?? 'Failed to make plan public.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleHostCancelAndRefund(String planId, String reason, String? otherText) async {
    setState(() => _isLoadingCancellation = true);
    final res = await ApiService.cancelPartyPlanDetailed(
      planId,
      reason: reason == 'other' ? otherText : reason,
    );
    if (!mounted) return;
    setState(() {
      _isLoadingCancellation = false;
      if (res?['success'] == true) {
        widget.plan['status'] = 'cancelled';
        widget.plan['lifecycleStatus'] = 'cancelled';
        widget.plan['isLive'] = false;
      }
    });

    if (res?['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res?['message'] ?? 'Party Plan cancelled. ${_getEffectiveRefundText()} has been refunded to your Lunara Wallet.'),
          backgroundColor: Colors.green,
        ),
      );
      _checkRequestStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res?['message'] ?? 'Failed to cancel party plan'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleHostRepostFlow(String planId, String reason, String? otherText) async {
    final now = DateTime.now();
    final initialDate = now.add(const Duration(hours: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: LunaraTheme.electricViolet,
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A24),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: LunaraTheme.electricViolet,
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A24),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedTime == null || !mounted) return;

    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (newDateTime.difference(DateTime.now()).inMinutes < 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a time at least 30 minutes in the future.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoadingCancellation = true);
    final res = await ApiService.repostPartyPlan(
      planId,
      newDateTime: newDateTime,
      reason: reason == 'other' ? otherText : reason,
    );
    if (!mounted) return;
    setState(() => _isLoadingCancellation = false);

    if (res?['success'] == true) {
      setState(() {
        widget.plan['planDateTime'] = newDateTime.toUtc().toIso8601String();
        widget.plan['status'] = 'active';
        widget.plan['lifecycleStatus'] = 'posted';
        widget.plan['isLive'] = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Party Plan reposted for ${DateFormat('dd MMM, hh:mm a').format(newDateTime)}!'),
          backgroundColor: Colors.green,
        ),
      );
      _checkRequestStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res?['message'] ?? 'Failed to repost party plan'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _submitCancellationRequest(String reason, String? otherText) async {
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) return;

    setState(() => _isLoadingCancellation = true);
    final res = await ApiService.requestPartyPlanCancellation(
      planId: planId,
      reason: reason,
      otherReasonText: otherText,
    );
    if (!mounted) return;
    setState(() => _isLoadingCancellation = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancellation request sent. Waiting for the other participant to approve.'), backgroundColor: Colors.orangeAccent),
      );
      _fetchCurrentUserAndCancellationState();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Failed to send cancellation request'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _respondToCancellation(String requestId, String action) async {
    final planId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) return;

    setState(() => _isLoadingCancellation = true);
    final res = await ApiService.respondToPartyPlanCancellationRequest(
      planId: planId,
      requestId: requestId,
      action: action,
    );
    if (!mounted) return;
    setState(() => _isLoadingCancellation = false);

    final bool isSuccess = res['success'] == true ||
        res['alreadyProcessed'] == true ||
        res['alreadyCancelled'] == true;

    if (isSuccess) {
      if (action == 'approve' || res['alreadyCancelled'] == true) {
        ApiService.markPartyPlanAsCancelledLocal(planId);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? (action == 'approve' ? 'Party Plan cancelled. ${_getEffectiveRefundText()} Commitment Deposit credited to your Lunara Wallet!' : 'Cancellation request declined.')),
          backgroundColor: action == 'approve' ? Colors.green : Colors.grey.shade800,
        ),
      );
      _fetchCurrentUserAndCancellationState();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Action failed'), backgroundColor: Colors.red),
      );
    }
  }

  bool _isCancelledPlan(Map<String, dynamic> plan) {
    final status = (plan['status'] ?? '').toString().toLowerCase();
    final lifecycleStatus = (plan['lifecycleStatus'] ?? plan['lifecycle_status'] ?? '').toString().toLowerCase();
    final bool cancelApproved = (_cancellationRequest != null && _cancellationRequest!['status'] == 'approved') ||
        ((plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'approved') ||
        (plan['cancellationRequest'] != null && (plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'approved');
    return status == 'cancelled' || lifecycleStatus == 'cancelled' || plan['isCancelled'] == true || cancelApproved;
  }

  Widget _buildCancellationSection() {
    if (_isStatusLoading) {
      return const SizedBox.shrink();
    }
    final bool isHost = _isHostPlan(widget.plan);
    final bool isConfirmed = _isPlanFullyConfirmed();
    final bool hasApprovedCancellation = (_cancellationRequest != null && _cancellationRequest!['status'] == 'approved') ||
        ((widget.plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'approved') ||
        (widget.plan['cancellationRequest'] != null && (widget.plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'approved');
    final bool isCancelled = _isCancelledPlan(widget.plan) && (!isConfirmed || hasApprovedCancellation);

    if (_isExpired) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: const Row(
          children: [
            Icon(Icons.timer_off_rounded, color: Color(0xFF64748B), size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This Party Plan has expired. No further actions or join requests can be made.',
                style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (isCancelled) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This Party Plan has been cancelled. Commitment deposits have been credited to Lunara Wallets.',
                style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    final bool hasPendingCancellation = (_cancellationRequest != null && (_cancellationRequest!['status'] == 'pending' || _cancellationRequest!['status'] == 'approved')) ||
        ((widget.plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'pending') ||
        (widget.plan['cancellationRequest'] != null && ((widget.plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'pending' || (widget.plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'approved'));

    final planStatus = (widget.plan['status'] ?? '').toString().toLowerCase();
    final isExplicitlyClosedOrCompleted = planStatus == 'closed' ||
        widget.plan['lifecycleStatus'] == 'completed' ||
        widget.plan['status'] == 'completed';

    // A party plan is NEVER "no longer available" for the host or if it's confirmed or active/newly created!
    if (!isHost && isExplicitlyClosedOrCompleted && !isCancelled && !_isExpired && !hasPendingCancellation && !isConfirmed && !_alreadyRequested && !_isInvitedUser) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This Party Plan is no longer available.',
                style: TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (_isWindowClosed) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 18),
                SizedBox(width: 8),
                Text(
                  'BOOKING LOCKED',
                  style: TextStyle(color: Color(0xFFD97706), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'This Party Plan can no longer be cancelled because the cancellation window has closed (less than 3 hours before event start time).',
              style: TextStyle(color: Color(0xFF4B5563), fontSize: 12, height: 1.4),
            ),
          ],
        ),
      );
    }

    if (_cancellationRequest != null && _cancellationRequest!['status'] == 'pending') {
      final String reqId = _cancellationRequest!['id']?.toString() ?? '';
      final String requestedById = _cancellationRequest!['requestedById']?.toString() ?? '';
      final String recipientUserId = _cancellationRequest!['recipientUserId']?.toString() ?? '';
      final bool isRecipient = _currentUserId != null &&
          ((requestedById.isNotEmpty && requestedById != _currentUserId) ||
           (recipientUserId.isNotEmpty && recipientUserId == _currentUserId));
      final requesterObj = _cancellationRequest!['requester'] is Map ? Map<String, dynamic>.from(_cancellationRequest!['requester']) : null;
      final requesterName = requesterObj?['firstName'] ?? 'The other participant';
      final reasonKey = _cancellationRequest!['reason']?.toString() ?? '';

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

      if (isRecipient) {
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cancellation Request Received',
                      style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$requesterName wants to cancel this Party Plan.',
                style: const TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Reason: "$reasonText"',
                style: const TextStyle(color: Color(0xFF4B5563), fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
              const Text('If you approve:', style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Text('• Both Commitment Deposits (${_getEffectiveRefundText()}) will be credited to each user\'s Lunara Wallet.', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
              const Text('• Chat becomes read-only.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoadingCancellation ? null : () => _respondToCancellation(reqId, 'reject'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('KEEP PLAN', style: TextStyle(color: Color(0xFF4B5563), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoadingCancellation ? null : () => _respondToCancellation(reqId, 'approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('CONFIRM CANCELLATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      } else {
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cancellation Request Pending — Waiting for the other participant to approve.',
                  style: TextStyle(color: Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }
    }

    // Default: Show subtle red outline "Cancel Party Plan" button — for confirmed participant only (Host already has CANCEL in bottom CTA)
    if (!isHost && !isConfirmed) return const SizedBox.shrink();
    if (isHost || _isSoloConverted) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
        icon: const Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 18),
        label: const Text(
          'Cancel Party Plan',
          style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFFECACA), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: const Color(0xFFFEF2F2),
        ),
      ),
    );
  }

  String? _extractImageUrlFromAny(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      if (raw.trim().isEmpty) return null;
      return ApiService.formatImageUrl(raw);
    }
    if (raw is Map) {
      final possibleKeys = [
        'url',
        'filePath',
        'imageUrl',
        'coverImageUrl',
        'cover_image_url',
        'path',
        'image'
      ];
      for (final k in possibleKeys) {
        if (raw[k] is String && (raw[k] as String).trim().isNotEmpty) {
          final fmt = ApiService.formatImageUrl(raw[k] as String);
          if (fmt != null && fmt.isNotEmpty) return fmt;
        }
      }
    }
    if (raw is List && raw.isNotEmpty) {
      for (final item in raw) {
        final fmt = _extractImageUrlFromAny(item);
        if (fmt != null && fmt.isNotEmpty) return fmt;
      }
    }
    return null;
  }

  Future<void> _loadVenueDetailsIfNeeded() async {
    final bool isMyPost = _isHostPlan(widget.plan);
    final venue = _extractVenue(widget.plan);
    final venueName = venue['name']?.toString() ?? (widget.plan['venue'] is String ? widget.plan['venue'] as String : '');
    final bool isSecretVenue = widget.plan['showVenueDetails'] == false ||
        widget.plan['isSecret'] == true ||
        widget.plan['isSecretVenue'] == true ||
        venue['showVenueDetails'] == false ||
        venue['isSecret'] == true ||
        venue['isSecretVenue'] == true ||
        venueName.toUpperCase().contains('SECRET VENUE');
    final bool hide = isSecretVenue && !isMyPost && widget.plan['canSeeVenue'] != true;
    if (hide) return;

    final initialUrl = _getVenueImageUrl();
    if (initialUrl != null && initialUrl.isNotEmpty) return;

    final venueId = widget.plan['venueId']?.toString() ??
        venue['id']?.toString() ??
        '';
    if (venueId.isEmpty) return;

    try {
      final response = await ApiService.get('/api/venues/$venueId');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['venue'] is Map) {
          final v = Map<String, dynamic>.from(data['venue']);
          dynamic raw = v['coverImage'] ??
              v['coverImageUrl'] ??
              v['cover_image_url'] ??
              v['imageUrl'] ??
              v['image'] ??
              v['gallery'] ??
              v['images'];
          final formatted = _extractImageUrlFromAny(raw);
          if (mounted && formatted != null && formatted.isNotEmpty) {
            setState(() {
              _fetchedVenueImageUrl = formatted;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading venue details in PartyPlanDetailScreen: $e');
    }
  }

  double _getEffectivePaidAmount() {
    final dynamic rawAmt = widget.plan['refundAmount'] ??
        widget.plan['amountPaid'] ??
        widget.plan['paidAmount'] ??
        widget.plan['totalAmount'] ??
        widget.plan['depositAmount'] ??
        widget.plan['paymentAmount'] ??
        widget.plan['amount'] ??
        widget.plan['entryPrice'] ??
        widget.plan['chargesPerHead'];
    if (rawAmt != null) {
      final parsed = double.tryParse(rawAmt.toString());
      if (parsed != null && parsed > 0) return parsed;
    }
    return 99.0;
  }

  String _getEffectiveRefundText() {
    final amt = _getEffectivePaidAmount();
    return '₹${amt.toInt() == amt ? amt.toInt() : amt.toStringAsFixed(0)}';
  }

  String? _getVenueImageUrl() {
    if (_fetchedVenueImageUrl != null && _fetchedVenueImageUrl!.isNotEmpty) {
      return _fetchedVenueImageUrl;
    }
    final venue = _extractVenue(widget.plan);
    final plan = widget.plan;

    // Prioritize actual event banner/flyer/poster image over venue interior photos
    final List<dynamic> possibleBannerKeys = [
      plan['bannerUrl'],
      plan['bannerImage'],
      plan['banner'],
      plan['posterUrl'],
      plan['poster'],
      plan['flyer'],
      plan['eventBanner'],
      plan['coverImageUrl'],
      plan['imageUrl'],
      plan['image'],
      if (plan['upcomingNight'] is Map) ...[
        plan['upcomingNight']['bannerUrl'],
        plan['upcomingNight']['bannerImage'],
        plan['upcomingNight']['posterUrl'],
        plan['upcomingNight']['flyer'],
        plan['upcomingNight']['imageUrl'],
      ],
      if (plan['event'] is Map) ...[
        plan['event']['bannerUrl'],
        plan['event']['bannerImage'],
        plan['event']['posterUrl'],
        plan['event']['flyer'],
        plan['event']['imageUrl'],
      ],
      if (plan['party'] is Map) ...[
        plan['party']['bannerUrl'],
        plan['party']['bannerImage'],
        plan['party']['posterUrl'],
        plan['party']['flyer'],
        plan['party']['imageUrl'],
      ],
      venue['coverImage'],
      venue['coverImageUrl'],
      venue['cover_image_url'],
      venue['imageUrl'],
      venue['image'],
      venue['images'],
      venue['gallery'],
      plan['venueImageUrl'],
      plan['venue_image_url'],
      plan['venueImage'],
    ];

    for (final candidate in possibleBannerKeys) {
      final formatted = _extractImageUrlFromAny(candidate);
      if (formatted != null && formatted.isNotEmpty) {
        return formatted;
      }
    }
    return null;
  }

  Future<void> _checkRequestStatus() async {
    try {
      // The host has no join request for their own plan. Avoid deriving the
      // host CTA from participant request cache/state.
      if (_isHostPlan(widget.plan)) {
        if (mounted && _isStatusLoading) {
          setState(() => _isStatusLoading = false);
        }
        return;
      }
      final currentUserId = ApiService.currentUserId ?? _currentUserId ?? '';
      final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
      if (targetPlanId.isEmpty) {
        if (mounted && _isStatusLoading) {
          setState(() => _isStatusLoading = false);
        }
        return;
      }

      final bool isPartnerByPlan = _isPartnerPlan(widget.plan);
      final bool isPaidInitial = _isJoinerPaid(widget.plan);

      bool requested = isPartnerByPlan || _alreadyRequested;
      bool isInvited = _isInvitedUser;
      String? reqStatus = (isPartnerByPlan && isPaidInitial) ? 'confirmed' : (_requestStatus ?? 'payment_pending');
      String? reqId = _activeRequestId ?? widget.plan['requestId']?.toString() ?? widget.plan['activeRequestId']?.toString() ?? widget.plan['matchedRequestId']?.toString();
      bool foundInFreshList = false;

      // Check plan['requests'] first
      if (widget.plan['requests'] is List) {
        for (final r in widget.plan['requests']) {
          if (r is Map) {
            final requesterId = (r['requesterId'] ?? r['requester']?['id'] ?? r['userId'] ?? '').toString();
            if (currentUserId.isNotEmpty && requesterId == currentUserId) {
              foundInFreshList = true;
              reqId = r['id']?.toString() ?? reqId;
              final rawStatus = (r['status'] ?? 'pending').toString().toLowerCase();
              final joinerPaid = _isJoinerPaid(widget.plan, Map<String, dynamic>.from(r));
              reqStatus = joinerPaid ? 'confirmed' : (rawStatus == 'accepted' ? 'payment_pending' : rawStatus);
              if (rawStatus != 'cancelled' && rawStatus != 'rejected' && rawStatus != 'declined') {
                requested = true;
              }
              break;
            }
          }
        }
      }

      final myRequests = await ApiService.fetchMyPartyPlanRequests();

      for (final req in myRequests) {
        final planId = req['partyPlanId']?.toString() ?? req['planId']?.toString() ?? req['plan']?['id']?.toString();
        if (planId == targetPlanId) {
          foundInFreshList = true;
          reqId = req['id']?.toString() ?? reqId;
          final rawStatus = (req['status'] ?? 'pending').toString().toLowerCase();
          final joinerPaid = _isJoinerPaid(widget.plan, Map<String, dynamic>.from(req));
          reqStatus = joinerPaid ? 'confirmed' : (rawStatus == 'accepted' ? 'payment_pending' : rawStatus);

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

          if (rawStatus != 'cancelled' &&
              rawStatus != 'rejected' &&
              rawStatus != 'declined' &&
              rawStatus != 'payment_failed' &&
              !isPaymentExpired) {
            requested = true;
          } else if (!isPartnerByPlan) {
            // Cleared or expired request: clean up request reference so user can send a fresh request
            requested = false;
            reqId = null;
            reqStatus = isPaymentExpired ? 'payment_failed' : rawStatus;
          }

          final reqIsInvite = req['isInvite'] == true ||
              req['requestType'] == 'private_invite' ||
              req['isPrivateInvite'] == true ||
              req['invitedBy'] != null ||
              req['type'] == 'party_plan_invitation' ||
              req['type'] == 'invitation';
          if (reqIsInvite) {
            isInvited = true;
          }
          break;
        }
      }

      if (isPartnerByPlan) {
        requested = true;
        reqStatus = (isPaidInitial || _isJoinerPaid(widget.plan)) ? 'confirmed' : 'payment_pending';
      } else if (!foundInFreshList && _activeRequestId != null && _alreadyRequested) {
        requested = true;
        reqStatus = _requestStatus;
        reqId = _activeRequestId;
      }

      final planData = widget.plan;
      final hostId = (planData['userId'] ?? planData['hostId'] ?? planData['user']?['id'] ?? '').toString();
      final selectedUsers = planData['selectedUsers'] ?? planData['selectedUserIds'];
      final bool inSelectedUsers = selectedUsers is List && selectedUsers.any((u) => u?.toString() == currentUserId);
      if (currentUserId.isNotEmpty && currentUserId != hostId && (inSelectedUsers || planData['isInvite'] == true || planData['requestType'] == 'private_invite')) {
        isInvited = true;
      }

      if (isInvited && reqId == null) {
        reqId = targetPlanId;
      }

      if (mounted) {
        setState(() {
          _alreadyRequested = requested;
          _isInvitedUser = isInvited;
          _activeRequestId = reqId ?? _activeRequestId;
          _requestStatus = reqStatus ?? (_isInvitedUser ? 'pending' : null);
          _isStatusLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking request status in PartyPlanDetailScreen: $e');
      if (mounted) {
        setState(() {
          _isStatusLoading = false;
        });
      }
    }
  }

  Future<void> _handleAcceptInvite() async {
    final reqId = _activeRequestId ?? widget.plan['requestId']?.toString() ?? widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
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
          _requestStatus = isSelfPay ? (hostPaid ? 'confirmed' : 'accepted') : 'payment_pending';
          _alreadyRequested = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? '🎉 Invite Accepted!'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshPlanDetails();
        _checkRequestStatus();
        if (!isSelfPay) {
          _openDepositPaymentSheet();
        }
      } else {
        if (res?['code'] == 'PARTNER_ALREADY_SELECTED') {
          setState(() {
            _requestStatus = 'cancelled_partner_selected';
            _alreadyRequested = false;
          });
          _refreshPlanDetails();
        }
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

  Future<void> _handleDeclineInvite() async {
    final reqId = _activeRequestId ?? widget.plan['requestId']?.toString() ?? widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
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
        final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
        ApiService.markPartyPlanAsCancelledLocal(targetPlanId);
        setState(() {
          _alreadyRequested = false;
          _isInvitedUser = false;
          _requestStatus = 'declined';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitation declined'),
            backgroundColor: Colors.grey,
          ),
        );
        _refreshPlanDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to decline invitation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDecliningInvite = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error declining invite: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmRequestExit({required bool withdraw}) async {
    if (_activeRequestId == null || _activeRequestId!.isEmpty) return;
    final label = withdraw ? 'Withdraw request' : 'Cancel request';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label?'),
        content: Text(withdraw
            ? 'Your payment has not been completed. This closes your payment window.'
            : 'You can cancel this request before the host accepts it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('KEEP REQUEST')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(withdraw ? 'WITHDRAW' : 'CANCEL REQUEST'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final targetPlanId = widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    final reqId = _activeRequestId ?? '';
    if (reqId.isEmpty) return;

    if (!OptimisticActionGuard.start('CANCEL_PARTY_REQ:$reqId')) return;

    final prevAlreadyRequested = _alreadyRequested;
    final prevRequestStatus = _requestStatus;
    final prevActiveReqId = _activeRequestId;

    // Optimistic UI: immediately reflect cancelled state
    setState(() {
      _alreadyRequested = false;
      _requestStatus = 'cancelled';
      _activeRequestId = null;
      _isLoadingCancellation = false;
    });

    try {
      final success = withdraw
          ? await ApiService.withdrawPartyPlanRequest(reqId)
          : await ApiService.cancelPartyPlanRequest(reqId);
      if (!mounted) return;

      if (success) {
        if (targetPlanId.isNotEmpty) {
          ApiService.markPartyPlanAsCancelledLocal(targetPlanId);
        }
        final action = withdraw ? 'withdrawn' : 'cancelled';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request $action'),
          backgroundColor: Colors.green,
        ));
      } else {
        // Rollback
        setState(() {
          _alreadyRequested = prevAlreadyRequested;
          _requestStatus = prevRequestStatus;
          _activeRequestId = prevActiveReqId;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to update this request. Please refresh and try again.'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _alreadyRequested = prevAlreadyRequested;
          _requestStatus = prevRequestStatus;
          _activeRequestId = prevActiveReqId;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      OptimisticActionGuard.end('CANCEL_PARTY_REQ:$reqId');
    }
  }

  void _startRazorpayDirectPayment(String reqId, String venueName, {String? orderId, double depositAmount = 99.0}) async {
    String currentOrderId = (orderId ?? '').trim();
    String razorpayKey = 'rzp_test_123';

    try {
      if (currentOrderId.isEmpty) {
        final initRes = await ApiService.initiateJoinerPayment(reqId);
        if (initRes != null && initRes['success'] == true) {
          currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
          if (initRes['razorpayKeyId'] != null && initRes['razorpayKeyId'].toString().isNotEmpty) {
            razorpayKey = initRes['razorpayKeyId'].toString();
          }
        }
      }

      final isMock = razorpayKey == 'rzp_test_123' ||
          razorpayKey == 'your_razorpay_key_id' ||
          currentOrderId.isEmpty ||
          currentOrderId.startsWith('order_mock_') ||
          currentOrderId.startsWith('mock_') ||
          currentOrderId.startsWith('pay_direct_');

      if (isMock) {
        final ordId = currentOrderId.isNotEmpty ? currentOrderId : 'order_mock_direct';
        final confirmRes = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
          'userId': ApiService.currentUserId ?? '',
          'razorpay_order_id': ordId,
          'razorpay_payment_id': 'pay_direct_${DateTime.now().millisecondsSinceEpoch}',
          'razorpay_signature': 'mock_signature',
        });
        if (confirmRes.statusCode == 200 && mounted) {
          setState(() {
            _requestStatus = 'confirmed';
          });
          _refreshPlanDetails();
          _checkRequestStatus();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Safety Deposit Paid! Booking Confirmed!'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (mounted) {
          String msg = 'Payment Verification Failed';
          try {
            final b = jsonDecode(confirmRes.body);
            msg = b['message'] ?? b['error'] ?? msg;
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $msg'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      late Razorpay razorpay;
      razorpay = Razorpay();

      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
        final confirmRes = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
          'userId': ApiService.currentUserId ?? '',
          'razorpay_order_id': response.orderId ?? (currentOrderId.isNotEmpty ? currentOrderId : 'order_rzp_${DateTime.now().millisecondsSinceEpoch}'),
          'razorpay_payment_id': response.paymentId ?? 'pay_${DateTime.now().millisecondsSinceEpoch}',
          'razorpay_signature': response.signature ?? 'signature',
        });
        razorpay.clear();
        if (confirmRes.statusCode == 200 && mounted) {
          setState(() {
            _requestStatus = 'confirmed';
          });
          _refreshPlanDetails();
          _checkRequestStatus();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Safety Deposit Paid! Booking Confirmed!'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (mounted) {
          String msg = 'Payment Confirmation Failed';
          try {
            final b = jsonDecode(confirmRes.body);
            msg = b['message'] ?? b['error'] ?? msg;
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $msg'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });

      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) async {
        razorpay.clear();
        if ((response.code == 0 || response.code == 2) && (razorpayKey.startsWith('rzp_test_') || currentOrderId.startsWith('order_mock_'))) {
          final confirmRes = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
            'userId': ApiService.currentUserId ?? '',
            'razorpay_order_id': currentOrderId.isNotEmpty ? currentOrderId : 'order_mock_direct',
            'razorpay_payment_id': 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
            'razorpay_signature': 'mock_signature',
          });
          if (confirmRes.statusCode == 200 && mounted) {
            setState(() {
              _requestStatus = 'confirmed';
            });
            _refreshPlanDetails();
            _checkRequestStatus();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Safety Deposit Paid! Booking Confirmed!'),
                backgroundColor: Colors.green,
              ),
            );
            return;
          }
        }
        if (mounted) {
          final errText = (response.message != null && response.message!.isNotEmpty && response.message != 'Payment Failed')
              ? response.message!
              : 'Payment process cancelled or failed';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $errText'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });

      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
        razorpay.clear();
      });

      final options = <String, dynamic>{
        'key': razorpayKey,
        'amount': (depositAmount * 100).round(),
        'name': 'Lunara Party Deposit',
        'description': 'Safety deposit for Party Plan at $venueName',
        if (currentOrderId.isNotEmpty) 'order_id': currentOrderId,
        'prefill': {
          'contact': '9999999999',
          'email': 'user@lunara.app',
        },
        'theme': {
          'color': '#7C3AED',
        }
      };

      razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open payment screen. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _openDepositPaymentSheet() async {
    final reqId = _activeRequestId ??
        widget.plan['requestId']?.toString() ??
        widget.plan['activeRequestId']?.toString() ??
        widget.plan['matchedRequestId']?.toString() ??
        (widget.plan['myRequest'] is Map ? widget.plan['myRequest']['id']?.toString() : null) ??
        (widget.plan['acceptedJoinerRequest'] is Map ? widget.plan['acceptedJoinerRequest']['id']?.toString() : null) ??
        (widget.plan['request'] is Map ? widget.plan['request']['id']?.toString() : null);
    if (reqId == null || reqId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to locate request ID. Please try refreshing.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final venue = _extractVenue(widget.plan);
    final venueName = venue['name']?.toString() ?? (widget.plan['venue'] is String ? widget.plan['venue'] as String : 'Venue');

    final double depositAmt = _getEffectivePaidAmount();
    final bool? sheetSuccess = await SmartCheckoutSheet.show(
      context: context,
      title: 'Party Plan Safety Deposit',
      subtitle: 'Safety commitment deposit for Party Plan at $venueName',
      itemPrice: depositAmt,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: depositAmt,
          planId: widget.plan['id']?.toString() ?? widget.plan['planId']?.toString(),
          paymentType: 'commitment_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = await ApiService.post('/api/mobile/party-plans/requests/$reqId/joiner-pay', body: {
            'userId': ApiService.currentUserId ?? '',
            'razorpay_order_id': 'order_mock_wallet',
            'razorpay_payment_id': 'wallet_$transactionId',
            'razorpay_signature': 'mock_signature',
          });
          if (confirmRes.statusCode == 200) {
            return true;
          } else {
            String msg = 'Payment Confirmation Failed';
            try {
              final b = jsonDecode(confirmRes.body);
              msg = b['message'] ?? b['error'] ?? msg;
            } catch (_) {}
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Payment Failed: $msg'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
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
        _startRazorpayDirectPayment(reqId, venueName);
      },
      onHybridPayment: (shortfall) async {
        _startRazorpayDirectPayment(reqId, venueName, depositAmount: shortfall > 0 ? shortfall : 99.0);
      },
    );

    if (sheetSuccess == true && mounted) {
      TopNotificationBanner.show(
        title: 'Safety Deposit Confirmed! 🎉',
        body: 'Your commitment deposit was paid via Smart Wallet. Booking confirmed!',
      );
      setState(() {
        _requestStatus = 'confirmed';
      });
      ApiService.notifyFeedNeedsRefresh();
      await _refreshPlanDetails();
      await _checkRequestStatus();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PartyPlanTicketScreen(
              request: const {},
              plan: widget.plan,
              isHost: false,
            ),
          ),
        );
      }
    }
  }

  void _openHostDepositPaymentSheet() async {
    if (_isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Party Plan has expired. No actions can be performed.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final cleanPlanId = widget.plan['id']?.toString() ?? '';
    final venue = _extractVenue(widget.plan);
    final venueName = venue['name']?.toString() ?? (widget.plan['venue'] is String ? widget.plan['venue'] as String : 'Venue');

    final double hostDepositAmt = _getEffectivePaidAmount();
    final bool? sheetSuccess = await SmartCheckoutSheet.show(
      context: context,
      title: 'Host Safety Deposit',
      subtitle: 'Publish & activate your Party Plan at $venueName',
      itemPrice: hostDepositAmt,
      onWalletPayment: () async {
        final res = await ApiService.payWithWallet(
          amount: hostDepositAmt,
          planId: cleanPlanId,
          paymentType: 'host_deposit',
        );
        if (res != null && res['success'] == true) {
          final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
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
        await _launchHostRazorpay(cleanPlanId, venueName, hostDepositAmt);
      },
      onHybridPayment: (shortfall) async {
        await _launchHostRazorpay(cleanPlanId, venueName, shortfall > 0 ? shortfall : hostDepositAmt);
      },
    );

    if (sheetSuccess == true && mounted) {
      TopNotificationBanner.show(
        title: 'Plan Activated! 🎉',
        body: 'Host Safety Deposit paid via Smart Wallet! Your plan is now LIVE.',
      );
      setState(() {
        widget.plan['hostPaymentStatus'] = 'paid';
        widget.plan['isLive'] = true;
      });
      ApiService.notifyFeedNeedsRefresh();
      await _refreshPlanDetails();
    }
  }

  Future<void> _launchHostRazorpay(String cleanPlanId, String venueName, double depositAmount) async {
    final initRes = await ApiService.initiateHostPayment(cleanPlanId);
    String currentOrderId = '';
    String razorpayKey = 'rzp_test_123';
    if (initRes != null && initRes['success'] == true) {
      currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
      if (initRes['razorpayKeyId'] != null && initRes['razorpayKeyId'].toString().isNotEmpty) {
        razorpayKey = initRes['razorpayKeyId'].toString();
      }
    }

    if (currentOrderId.isEmpty) {
      currentOrderId = 'order_mock_${DateTime.now().millisecondsSinceEpoch}';
    }

    if (currentOrderId.startsWith('order_mock_') || razorpayKey == 'rzp_test_123' || currentOrderId.startsWith('mock_')) {
      final paymentConfirmed = await ApiService.verifyHostPayment(
        cleanPlanId,
        currentOrderId,
        'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        'mock_signature',
      );
      if (paymentConfirmed && mounted) {
        setState(() {
          widget.plan['hostPaymentStatus'] = 'paid';
          widget.plan['isLive'] = true;
        });
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

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      final pId = response.paymentId ?? 'pay_mock_${DateTime.now().millisecondsSinceEpoch}';
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
        setState(() {
          widget.plan['hostPaymentStatus'] = 'paid';
          widget.plan['isLive'] = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Host Safety Deposit Paid! Your plan is live.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      razorpay.clear();
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open payment screen. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return 'TBD';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('EEE, dd MMM yyyy • hh:mm a').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _sendJoinRequest() async {
    if (_isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Party Plan has expired. No requests can be sent.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_alreadyRequested) return;

    final planId =
        widget.plan['planId']?.toString() ?? widget.plan['id']?.toString() ?? '';
    if (planId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid plan ID.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!OptimisticActionGuard.start('JOIN_PARTY_PLAN:$planId')) return;

    final prevAlreadyRequested = _alreadyRequested;
    final prevRequestStatus = _requestStatus;
    final prevIsInvited = _isInvitedUser;
    final prevActiveReqId = _activeRequestId;

    setState(() {
      _isJoining = true;
    });

    try {
      final res = await ApiService.requestToJoinPartyPlanDetailed(planId);
      if (!mounted) return;
      if (res.alreadyRequested || res.success) {
        setState(() {
          _isJoining = false;
          _alreadyRequested = true;
          _isInvitedUser = false;
          _activeRequestId = res.requestId ?? _activeRequestId;
          _requestStatus = res.status ?? 'pending';
        });
        if (res.isNewRequest) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
              content: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
        // Server rejected: rollback
        setState(() {
          _isJoining = false;
          _alreadyRequested = prevAlreadyRequested;
          _requestStatus = prevRequestStatus;
          _isInvitedUser = prevIsInvited;
          _activeRequestId = prevActiveReqId;
        });
        final msg = res.message.toLowerCase();
        if (msg.contains('no longer available') ||
            msg.contains('not active') ||
            msg.contains('party_plan_not_active') ||
            msg.contains('another partner')) {
          ApiService.markPartyPlanAsCancelledLocal(planId);
          ApiService.invalidateLiveFeedCache();
          ApiService.notifyFeedNeedsRefresh();
          setState(() {
            widget.plan['status'] = 'cancelled';
            widget.plan['isLive'] = false;
          });
        }

        if (TimeLockBlockedDialog.isConflictError(res.message) ||
            (res.rawData != null && res.rawData!['allowed'] == false)) {
          TimeLockBlockedDialog.show(
            context,
            errorData: res.rawData ?? {'message': res.message},
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TimeLockBlockedDialog.cleanErrorMessage(res.message)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      // Network/unexpected failure: rollback
      setState(() {
        _isJoining = false;
        _alreadyRequested = prevAlreadyRequested;
        _requestStatus = prevRequestStatus;
        _isInvitedUser = prevIsInvited;
        _activeRequestId = prevActiveReqId;
      });

      final errStr = e.toString().toLowerCase();
      if (errStr.contains('no longer available') ||
          errStr.contains('not active') ||
          errStr.contains('party_plan_not_active') ||
          errStr.contains('another partner')) {
        ApiService.markPartyPlanAsCancelledLocal(planId);
        ApiService.invalidateLiveFeedCache();
        ApiService.notifyFeedNeedsRefresh();
        setState(() {
          widget.plan['status'] = 'cancelled';
          widget.plan['isLive'] = false;
        });
      }

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
    } finally {
      OptimisticActionGuard.end('JOIN_PARTY_PLAN:$planId');
    }
  }

  void _showHostDetails(BuildContext ctx, Map<String, dynamic> host) {
    final hostName = host['name'] as String? ?? 'Unknown';
    final hostAge = host['age'];
    final hostOccupation = host['occupation'] as String? ?? '';
    final hostBio = host['bio'] as String? ?? '';

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              LunaraProfileImage(
                userData: host,
                radius: 40,
                showGradientBorder: true,
                isInteractive: false,
              ),
              const SizedBox(height: 14),
              Text(
                hostAge != null ? '$hostName, $hostAge' : hostName,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hostOccupation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  hostOccupation,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ],
              if (hostBio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  hostBio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  static Map<String, dynamic> _extractVenue(Map<String, dynamic> plan) {
    final raw = plan['venue'] ?? plan['venueMap'] ?? plan['venueDetails'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return {'name': raw.trim()};
    }
    final venueName = plan['venueName']?.toString().trim();
    if (venueName != null && venueName.isNotEmpty) {
      return {'name': venueName};
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _extractHost(Map<String, dynamic> plan) {
    if (plan['host'] is Map && (plan['host'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(plan['host']);
    }
    if (plan['user'] is Map && (plan['user'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(plan['user']);
    }
    if (plan['creator'] is Map && (plan['creator'] as Map).isNotEmpty) {
      return Map<String, dynamic>.from(plan['creator']);
    }
    final name = plan['hostName'] ?? plan['userName'] ?? (plan['hostFirstName'] != null ? '${plan['hostFirstName']} ${plan['hostLastName'] ?? ''}'.trim() : null);
    final photo = plan['hostProfilePhotoUrl'] ?? plan['hostPhotoUrl'] ?? plan['profileImageUrl'] ?? plan['userPhotoUrl'];
    return {
      'id': plan['userId'] ?? plan['hostId'],
      'name': name ?? 'Party Host',
      'firstName': plan['hostFirstName'] ?? name,
      'lastName': plan['hostLastName'],
      'profilePhotoUrl': photo,
      'profileImageUrl': photo,
      'bio': plan['hostBio'],
      'occupation': plan['hostOccupation'],
      'age': plan['hostAge'],
    };
  }

  bool _isHostPlan(Map<String, dynamic> plan) {
    final currentUid = ApiService.currentUserId ?? _currentUserId ?? '';
    if (currentUid.isEmpty) return false;

    final role = (plan['role'] ?? plan['viewerRole'] ?? '').toString().toLowerCase();
    if (role == 'host' || role == 'creator') return true;

    final host = _extractHost(plan);
    final creator = plan['creator'] is Map ? plan['creator'] as Map : const <String, dynamic>{};
    final user = plan['user'] is Map ? plan['user'] as Map : const <String, dynamic>{};
    return [
      host['id'],
      plan['userId'],
      plan['hostId'],
      creator['id'],
      user['id'],
    ].any((id) => id?.toString() == currentUid);
  }

  bool _isPartnerPlan(Map<String, dynamic> plan) {
    final currentUid = ApiService.currentUserId ?? _currentUserId ?? '';
    if (currentUid.isEmpty) return false;

    final role = (plan['role'] ?? plan['viewerRole'] ?? '').toString().toLowerCase();
    if (role == 'partner' || role == 'joiner' || role == 'guest') return true;

    if (plan['isAcceptedJoiner'] == true) return true;

    final partnerId = (plan['partnerId'] ?? plan['partner_id'])?.toString();
    if (partnerId != null && partnerId.isNotEmpty && partnerId == currentUid) return true;

    if (plan['matchedPartner'] is Map) {
      final mpId = (plan['matchedPartner']['id'] ?? plan['matchedPartner']['userId'])?.toString();
      if (mpId != null && mpId == currentUid) return true;
    }
    if (plan['partner'] is Map) {
      final pId = (plan['partner']['id'] ?? plan['partner']['userId'])?.toString();
      if (pId != null && pId == currentUid) return true;
    }
    if (plan['acceptedJoinerRequest'] is Map) {
      final reqId = (plan['acceptedJoinerRequest']['requesterId'] ?? plan['acceptedJoinerRequest']['requester']?['id'] ?? plan['acceptedJoinerRequest']['userId'])?.toString();
      if (reqId != null && reqId == currentUid) return true;
    }
    return false;
  }

  bool _isJoinerPaid(Map<String, dynamic> plan, [Map<String, dynamic>? request]) {
    // If cancellation request is pending or approved, both parties are confirmed/paid
    final bool hasPendingCancellation = (_cancellationRequest != null && (_cancellationRequest!['status'] == 'pending' || _cancellationRequest!['status'] == 'approved')) ||
        ((plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'pending') ||
        (plan['cancellationRequest'] != null && ((plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'pending' || (plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'approved'));
    if (hasPendingCancellation) return true;

    // If self_pay and host is paid, joiner doesn't need to pay deposit
    final paymentType = (plan['paymentType'] ?? '').toString().toLowerCase();
    final hostPaid = (plan['hostPaymentStatus'] ?? '').toString().toLowerCase() == 'paid' ||
        (plan['paymentStatus'] ?? '').toString().toLowerCase() == 'confirmed';
    if (paymentType == 'self_pay' && hostPaid) return true;

    // Check request joinerPaymentStatus / isPaid
    if (request?['isPaid'] == true || request?['paid'] == true || request?['hasPaid'] == true) return true;
    final reqJoinerPay = (request?['joinerPaymentStatus'] ?? request?['paymentStatus'] ?? '').toString().toLowerCase();
    if (reqJoinerPay == 'paid' || reqJoinerPay == 'completed') return true;
    if (reqJoinerPay == 'unpaid' || reqJoinerPay == 'pending') return false;

    // Check plan-level joiner payment status
    if (plan['isPaid'] == true || plan['paid'] == true || plan['hasPaid'] == true) return true;
    final planJoinerPay = (plan['joinerPaymentStatus'] ?? plan['guestPaymentStatus'] ?? plan['userPaymentStatus'] ?? '').toString().toLowerCase();
    if (planJoinerPay == 'paid' || planJoinerPay == 'completed') return true;
    if (planJoinerPay == 'unpaid' || planJoinerPay == 'pending') return false;

    final reqStatus = (request?['status'] ?? _requestStatus ?? plan['requestStatus'] ?? '').toString().toLowerCase();
    if (reqStatus == 'payment_pending' || reqStatus == 'accepted' || reqStatus == 'pending') return false;
    if (reqStatus == 'confirmed' || reqStatus == 'paid' || reqStatus == 'approved') return true;

    final life = (plan['lifecycleStatus'] ?? '').toString().toLowerCase();
    if (life == 'payment_pending' || life == 'host_payment_completed' || life == 'user_accepted') return false;
    if (life == 'match_confirmed' || life == 'chat_enabled' || life == 'arrival_confirmation' || life == 'event_reminder' || life == 'plan_completed') {
      return true;
    }

    return false;
  }

  String _extractHostName(Map<String, dynamic> host, Map<String, dynamic> plan) {
    final name = host['name'] ?? host['fullName'];
    if (name != null && name.toString().trim().isNotEmpty && name.toString().trim() != 'Unknown') {
      return name.toString().trim();
    }
    final fn = host['firstName'] ?? plan['hostFirstName'];
    final ln = host['lastName'] ?? plan['hostLastName'];
    if (fn != null && fn.toString().trim().isNotEmpty) {
      return '$fn ${ln ?? ''}'.trim();
    }
    if (plan['hostName'] != null && plan['hostName'].toString().isNotEmpty && plan['hostName'].toString() != 'Unknown') {
      return plan['hostName'].toString();
    }
    return 'Party Host';
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final host = _extractHost(plan);
    final venue = _extractVenue(plan);

    // `requesterId` is deliberately not treated as host ownership. It belongs
    // to a participant request and previously made role inference ambiguous.
    final isMyPost = _isHostPlan(plan);
    final venueName = venue['name']?.toString() ?? (plan['venue'] is String ? plan['venue'] as String : 'Venue');

    // canSeeVenue is the backend-authoritative flag (host, or a joiner the
    // host has accepted). Hosts always see their own venue regardless.
    final bool isSecretVenue = plan['showVenueDetails'] == false ||
        plan['isSecret'] == true ||
        plan['isSecretVenue'] == true ||
        venue['showVenueDetails'] == false ||
        venue['isSecret'] == true ||
        venue['isSecretVenue'] == true ||
        venueName.toUpperCase().contains('SECRET VENUE');
    final bool hideVenueDetails = isSecretVenue && !isMyPost && plan['canSeeVenue'] != true;

    final hostName = _extractHostName(host, plan);
    final hostAge = host['age'] ?? plan['hostAge'];
    final hostOccupation = host['occupation'] as String? ?? plan['hostOccupation'] as String? ?? '';
    final hostBio = host['bio'] as String? ?? plan['hostBio'] as String? ?? '';

    final venueAddress =
        [venue['addressLine1'], venue['area'], venue['city']]
            .where((e) => e != null && e.toString().isNotEmpty)
            .join(', ');

    final description = plan['description'] as String? ?? '';
    final planDateRaw = plan['planDateTime'] ?? plan['planDate'];
    final formattedDate = _formatDateTime(planDateRaw);
    final visibility = (plan['visibility'] as String? ?? 'public').toUpperCase();
    final status = (plan['status'] as String? ?? 'active').toUpperCase();

    final venueImageUrl = _getVenueImageUrl();

    final hasBasicData = plan['title'] != null ||
        plan['venue'] != null ||
        plan['venueName'] != null ||
        plan['user'] != null ||
        plan['userId'] != null ||
        plan['hostId'] != null ||
        plan['hostName'] != null ||
        plan['description'] != null;

    if (_isStatusLoading && !hasBasicData) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(LunaraTheme.electricViolet),
            ),
          ),
        ),
      );
    }

    final bool isConfirmed = _isPlanFullyConfirmed();
    final bool isCancelled = _isCancelledPlan(plan);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.white,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  child: IconButton(
                    icon: const Icon(Icons.person_rounded, color: Color(0xFF1E293B)),
                    onPressed: () => _showHostDetails(context, host),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient background
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2D0060), Color(0xFF0D001C)],
                      ),
                    ),
                  ),
                  // Venue Image if available (hidden until this viewer can see the venue)
                  if (hideVenueDetails)
                    const _SecretVenueImagePlaceholder()
                  else if (venueImageUrl != null && venueImageUrl.isNotEmpty)
                    LunaraCachedImage(
                      venueImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _VenueImageFallback(),
                    )
                  else
                    const _VenueImageFallback(),
                  // Dark overlay gradient for contrast
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                  // Host info overlay
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _showHostDetails(context, host),
                          child: LunaraProfileImage(
                            userData: host,
                            radius: 34,
                            showGradientBorder: true,
                            isInteractive: false,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      hostAge != null
                                          ? '$hostName, $hostAge'
                                          : hostName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (hostOccupation.isNotEmpty)
                                Text(
                                  hostOccupation,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Party Plan badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
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
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body Content ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Row
                  Row(
                    children: [
                      _chip(
                        icon: _isStatusLoading
                            ? Icons.hourglass_top_rounded
                            : (_isSoloConverted
                                ? Icons.confirmation_number_rounded
                                : (_isExpired
                                    ? Icons.timer_off_rounded
                                    : (isConfirmed
                                        ? Icons.verified_rounded
                                        : (isCancelled ? Icons.cancel_rounded : Icons.circle)))),
                        label: _isStatusLoading
                            ? 'CHECKING...'
                            : (_isSoloConverted
                                ? 'SOLO TICKET'
                                : (_isExpired
                                    ? 'EXPIRED'
                                    : (isConfirmed
                                        ? 'CONFIRMED'
                                        : (isCancelled ? 'CANCELLED' : status)))),
                        color: _isStatusLoading
                            ? const Color(0xFF94A3B8)
                            : (_isSoloConverted
                                ? const Color(0xFF8B5CF6)
                                : (_isExpired
                                    ? const Color(0xFF94A3B8)
                                    : (isConfirmed
                                        ? const Color(0xFF10B981)
                                        : (isCancelled ? const Color(0xFFDC2626) : (status == 'ACTIVE' ? const Color(0xFF10B981) : const Color(0xFF94A3B8)))))),
                      ),
                      const SizedBox(width: 8),
                      _chip(
                        icon: visibility == 'PUBLIC' ? Icons.public_rounded : Icons.lock_rounded,
                        label: visibility,
                        color: visibility == 'PUBLIC'
                            ? LunaraTheme.accentVivid
                            : const Color(0xFFD97706),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Description
                  if (description.isNotEmpty) ...[
                    const Text(
                      'ABOUT THIS PLAN',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Host Bio
                  if (hostBio.isNotEmpty) ...[
                    const Text(
                      'HOST BIO',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hostBio,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Pending Requests Section (For Host)
                  if (isMyPost && _pendingRequests.isNotEmpty && !_isExpired)
                    _buildPendingRequestsSection(),

                  // Date / Time Card
                  _infoCard(
                    icon: Icons.calendar_today_rounded,
                    title: 'DATE & TIME',
                    value: formattedDate,
                    iconColor: LunaraTheme.accentVivid,
                  ),
                  const SizedBox(height: 12),

                  // Preferences Card
                  _infoCard(
                    icon: Icons.restaurant_menu_rounded,
                    title: 'FOOD & DRINK PREFERENCES',
                    value: 'Food: ${plan['foodPreference'] ?? 'Both'}',
                    subtitle: 'Drink: ${plan['drinkPreference'] ?? 'Both'}',
                    iconColor: const Color(0xFFD97706),
                  ),
                  const SizedBox(height: 12),

                  // Venue Card with Privacy Masking (Step 3)
                  _infoCard(
                    icon: hideVenueDetails ? Icons.visibility_off_rounded : Icons.location_on_rounded,
                    title: 'VENUE',
                    value: hideVenueDetails
                        ? '${venue['area'] ?? venue['city'] ?? 'Near Area'} (Exact venue hidden until host approval)'
                        : venueName,
                    subtitle: hideVenueDetails
                        ? 'Locality: ${venue['area'] ?? venue['city'] ?? 'Local Area'}'
                        : venueAddress,
                    iconColor: hideVenueDetails ? const Color(0xFFD97706) : LunaraTheme.electricViolet,
                  ),

                  // 24-hour "no partner yet" prompt for event-linked plans
                  if (isMyPost && _hasNoMatchPrompt && !isCancelled && !_isExpired && !_isSoloConverted) ...[
                    _buildNoMatchActionPromptSection(),
                    const SizedBox(height: 16),
                  ],

                  // Mutual Cancellation Section
                  if (!_isExpired) ...[
                    _buildCancellationSection(),
                    const SizedBox(height: 30),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom CTA ───────────────────────────────────────────────────────
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _buildBottomCTA(isMyPost) ?? const SizedBox.shrink(key: ValueKey('empty_cta')),
      ),
    );
  }

  Widget? _buildBottomCTA(bool isMyPost) {
    if (_isStatusLoading) {
      return SafeArea(
        key: const ValueKey('cta_status_loading'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
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
          ),
        ),
      );
    }

    final plan = widget.plan;
    final planStatus = (plan['status'] ?? '').toString().toLowerCase();
    final lifecycleStatus = (plan['lifecycleStatus'] ?? plan['lifecycle_status'] ?? '').toString().toLowerCase();
    final isPlanCancelled = planStatus == 'cancelled' || lifecycleStatus == 'cancelled';

    if (isPlanCancelled) {
      return SafeArea(
        key: const ValueKey('cta_plan_cancelled'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 22),
                SizedBox(width: 10),
                Text(
                  'PLAN CANCELLED BY HOST',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_isExpired) {
      return _expiredBanner();
    }
    if (isMyPost) {
      return _myPlanBanner();
    }

    final currentUserId = ApiService.currentUserId ?? _currentUserId ?? '';
    final String matchedReqId = (plan['matchedRequestId'] ?? plan['matched_request_id'] ?? '').toString();
    final String partnerId = (plan['partnerId'] ?? plan['partner_id'] ?? '').toString();
    final bool isPartnerByPlan = _isPartnerPlan(plan);
    final bool joinerPaid = _isJoinerPaid(plan);
    final bool hasPendingCancellation = (_cancellationRequest != null && (_cancellationRequest!['status'] == 'pending' || _cancellationRequest!['status'] == 'approved')) ||
        ((plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'pending') ||
        (plan['cancellationRequest'] != null && ((plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'pending' || (plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'approved'));
    final bool isMyRequestConfirmed = hasPendingCancellation || (joinerPaid && (isPartnerByPlan || (_alreadyRequested && (_requestStatus == 'confirmed' || _requestStatus == 'paid'))));

    // Only show "partner already selected" to viewers who had an active request
    // that was displaced. A fresh user with no request should see "Request to Join".
    final bool hadActiveRequest = _alreadyRequested ||
        _activeRequestId != null ||
        _requestStatus == 'cancelled_partner_selected' ||
        plan['reason'] == 'partner_already_selected' ||
        plan['cancellationReason'] == 'partner_already_selected' ||
        planStatus == 'partner_already_selected';

    final bool isMatchedWithAnother = !isMyPost && !isMyRequestConfirmed && hadActiveRequest && (
      (matchedReqId.isNotEmpty && (_activeRequestId == null || _activeRequestId != matchedReqId) && !isPartnerByPlan) ||
      (partnerId.isNotEmpty && (currentUserId.isEmpty || partnerId != currentUserId)) ||
      _requestStatus == 'cancelled_partner_selected' ||
      plan['reason'] == 'partner_already_selected' ||
      plan['cancellationReason'] == 'partner_already_selected' ||
      planStatus == 'partner_already_selected'
    );

    if (isMatchedWithAnother) {
      return _partnerAlreadySelectedBanner();
    }

    final bool isExplicitlyClosedOrCompleted = planStatus == 'closed' ||
        plan['lifecycleStatus'] == 'completed' ||
        plan['status'] == 'completed';

    final bool isConfirmed = _isPlanFullyConfirmed();

    if (!isMyPost && isExplicitlyClosedOrCompleted && !isMyRequestConfirmed && !hasPendingCancellation && !isConfirmed && !_alreadyRequested && !_isInvitedUser) {
      return SafeArea(
        key: const ValueKey('cta_plan_inactive'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Center(
              child: Text(
                'THIS PARTY PLAN IS NO LONGER AVAILABLE',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: isMyRequestConfirmed
            ? Row(
                children: [
                  // View Ticket
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final requestData = widget.plan['myRequest'] is Map
                            ? Map<String, dynamic>.from(widget.plan['myRequest'])
                            : (widget.plan['acceptedJoinerRequest'] is Map
                                ? Map<String, dynamic>.from(widget.plan['acceptedJoinerRequest'])
                                : <String, dynamic>{});
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartyPlanTicketScreen(
                              request: requestData,
                              plan: widget.plan,
                              isHost: false,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: LunaraTheme.purpleGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'TICKET',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Open Chat
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final host = _extractHost(widget.plan);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(user: {
                              ...host,
                              'contextType': 'party_plan',
                              'planId': widget.plan['id']?.toString(),
                            }),
                          ),
                        );
                      },
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6D28D9), Color(0xFF9333EA)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'CHAT',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!_isWindowClosed &&
                      !((_cancellationRequest != null && _cancellationRequest!['status'] == 'pending') || widget.plan['cancellationStatus'] == 'pending') &&
                      !(widget.plan['status'] == 'cancelled' || widget.plan['cancellationStatus'] == 'cancelled')) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
                      child: Container(
                        height: 54,
                        width: 54,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: Center(
                          child: _isLoadingCancellation
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.redAccent),
                                  ),
                                )
                              : const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 20),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : (_alreadyRequested && _requestStatus == 'pending' && !_isInvitedUser)
            ? SizedBox(
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _isLoadingCancellation ? null : () => _confirmRequestExit(withdraw: false),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('CANCEL REQUEST', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                ),
              )
            : (!hasPendingCancellation && !joinerPaid && (_alreadyRequested || isPartnerByPlan) && (_requestStatus == 'accepted' || _requestStatus == 'payment_pending'))
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _openDepositPaymentSheet,
                    child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00C853).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.payment_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'PAY SAFETY DEPOSIT (${_getEffectiveRefundText()})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoadingCancellation ? null : () => _confirmRequestExit(withdraw: true),
                    child: const Text('WITHDRAW REQUEST', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            : (_isInvitedUser && (_requestStatus == 'pending' || _requestStatus == 'invited' || _requestStatus == null))
                ? Row(
                    children: [
                      // Decline Button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 58,
                          child: OutlinedButton(
                            onPressed: (_isDecliningInvite || _isAcceptingInvite)
                                ? null
                                : _handleDeclineInvite,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: BorderSide(
                                color: Colors.redAccent.withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
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
                        child: GestureDetector(
                          onTap: (_isAcceptingInvite || _isDecliningInvite) ? null : _handleAcceptInvite,
                          child: Container(
                            height: 58,
                            decoration: BoxDecoration(
                              gradient: (_isAcceptingInvite || _isDecliningInvite) ? null : LunaraTheme.purpleGradient,
                              color: (_isAcceptingInvite || _isDecliningInvite) ? Colors.grey.withValues(alpha: 0.3) : null,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: (_isAcceptingInvite || _isDecliningInvite)
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isAcceptingInvite)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _isAcceptingInvite ? 'ACCEPTING...' : 'ACCEPT INVITE',
                                    style: const TextStyle(
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
                : _alreadyRequested
                    ? Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.4),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.green),
                                const SizedBox(width: 10),
                                const Text(
                                  'REQUEST SENT — AWAITING HOST APPROVAL',
                                  style: TextStyle(
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
                    : GestureDetector(
                        onTap: (_isJoining || _alreadyRequested) ? null : _sendJoinRequest,
                        child: Container(
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: _isJoining ? null : LunaraTheme.purpleGradient,
                            color: _isJoining ? Colors.grey.withValues(alpha: 0.3) : null,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: _isJoining
                                ? null
                                : [
                                    BoxShadow(
                                      color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isJoining)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                _isJoining ? 'SENDING REQUEST...' : 'REQUEST TO JOIN THE VIBE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
      ),
    );
  }

  Widget _myPlanBanner() {
    final plan = widget.plan;
    final lifecycleStatus = plan['lifecycleStatus']?.toString() ?? plan['lifecycle_status']?.toString() ?? '';
    final hostPaymentStatus = plan['hostPaymentStatus']?.toString() ?? plan['host_payment_status']?.toString() ?? '';
    final chatEnabled = plan['chatEnabled'] == true || plan['chat_enabled'] == true;
    final joinerPaid = _isJoinerPaid(plan);
    final bool hasPendingCancellation = (_cancellationRequest != null && (_cancellationRequest!['status'] == 'pending' || _cancellationRequest!['status'] == 'approved')) ||
        ((plan['cancellationStatus'] ?? '').toString().toLowerCase() == 'pending') ||
        (plan['cancellationRequest'] != null && ((plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'pending' || (plan['cancellationRequest']['status'] ?? '').toString().toLowerCase() == 'approved'));
    final isHostPaid = hostPaymentStatus == 'paid' || hostPaymentStatus == 'completed';
    final isHostPaysOnly = (plan['paymentType'] ?? plan['payment_type'] ?? '').toString().toLowerCase() == 'host_pays' ||
        (plan['paymentType'] ?? plan['payment_type'] ?? '').toString().toLowerCase() == 'i_pay' ||
        (plan['paymentType'] ?? plan['payment_type'] ?? '').toString().toLowerCase() == 'free';

    // Determine if the plan is fully confirmed (match locked and payments completed)
    final isConfirmed = hasPendingCancellation || (isHostPaid && (joinerPaid || isHostPaysOnly) && (
        chatEnabled ||
        lifecycleStatus == 'match_confirmed' ||
        lifecycleStatus == 'chat_enabled' ||
        lifecycleStatus == 'event_reminder' ||
        lifecycleStatus == 'arrival_confirmation' ||
        lifecycleStatus == 'both_arrived' ||
        lifecycleStatus == 'plan_completed'
    ));

    if (isConfirmed) {
      // Host sees: Ticket + Chat + Cancel after plan is matched
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              // View Ticket
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyPlanTicketScreen(
                          request: const {},
                          plan: plan,
                          isHost: true,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LunaraTheme.purpleGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'TICKET',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Open Chat
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Find partner from plan data
                    final partnerData = plan['matchedPartner'] ?? plan['partner'] ?? plan['guest'] ?? {};
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(user: {
                          ...(partnerData is Map ? Map<String, dynamic>.from(partnerData) : {}),
                          'contextType': 'party_plan',
                          'planId': plan['id']?.toString(),
                        }),
                      ),
                    );
                  },
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6D28D9), Color(0xFF9333EA)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'CHAT',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Cancel (Only when cancellation window is open and not already in cancellation)
              if (!_isWindowClosed &&
                  !((_cancellationRequest != null && _cancellationRequest!['status'] == 'pending') || widget.plan['cancellationStatus'] == 'pending') &&
                  !(widget.plan['status'] == 'cancelled' || widget.plan['cancellationStatus'] == 'cancelled')) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
                  child: Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 22),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Unpaid Host Deposit
    if (hostPaymentStatus != 'paid' && hostPaymentStatus != 'completed') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: GestureDetector(
            onTap: _openHostDepositPaymentSheet,
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                gradient: LunaraTheme.purpleGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.payment_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'PAY SAFETY DEPOSIT (${_getEffectiveRefundText()})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_isSoloConverted) {
      final venue = _extractVenue(widget.plan);
      final rawDate = widget.plan['planDateTime'] ?? widget.plan['bookingDate'] ?? widget.plan['date'];
      final rawTime = widget.plan['startTime'] ?? widget.plan['time'];
      final bookingData = widget.plan['booking'] is Map
          ? Map<dynamic, dynamic>.from(widget.plan['booking'])
          : <dynamic, dynamic>{
              'id': widget.plan['bookingId'] ?? widget.plan['id'],
              'venueId': widget.plan['venueId'],
              'venue': venue,
              'bookingDate': rawDate?.toString(),
              'startTime': rawTime?.toString() ?? '20:00',
              'ticketCode': widget.plan['ticketCode'] ?? widget.plan['ticketId'] ?? widget.plan['bookingId'] ?? widget.plan['id'],
              'ticketUrl': widget.plan['ticketUrl'],
              'totalAmount': _getEffectivePaidAmount(),
              'isUpcomingNight': true,
              'isSolo': true,
              'status': 'CONFIRMED',
            };

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DigitalTicketScreen(
                          venue: venue,
                          date: rawDate?.toString(),
                          time: rawTime?.toString() ?? '20:00',
                          table: 'Solo Entry',
                          package: 'Solo Entry',
                          guests: '1',
                          totalPrice: '₹${_getEffectivePaidAmount().toStringAsFixed(0)}',
                          ticketId: (widget.plan['ticketCode'] ?? widget.plan['bookingId'] ?? widget.plan['id'])?.toString(),
                          ticketUrl: widget.plan['ticketUrl']?.toString(),
                          status: 'CONFIRMED',
                          booking: bookingData,
                          isUpcomingNight: true,
                          user: ApiService.cachedCurrentUser,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LunaraTheme.purpleGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'VIEW TICKET',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!_isWindowClosed) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'CANCEL',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
      );
    }

    // Host Paid — show host label (+ CANCEL PLAN button only if window not closed)
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: LunaraTheme.primaryDeep.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: LunaraTheme.primaryDeep.withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star_rounded, color: LunaraTheme.electricViolet),
                    SizedBox(width: 8),
                    Text(
                      'YOUR PARTY PLAN',
                      style: TextStyle(
                        color: LunaraTheme.electricViolet,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_isWindowClosed) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _isLoadingCancellation ? null : _showCancellationStep1Dialog,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'CANCEL',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
    );
  }

  bool get _isSoloConverted {
    final p = widget.plan;
    final paymentStatus = (p['paymentStatus'] ?? '').toString().toLowerCase();
    final isSoloFlag = p['isSolo'] == true || p['goingMode'] == 'solo';
    final bookingId = p['bookingId'] ?? p['booking']?['id'];
    return isSoloFlag ||
        paymentStatus.contains('converted to solo') ||
        paymentStatus.contains('solo ticket') ||
        (p['partyEventId'] != null && bookingId != null);
  }

  bool get _hasNoMatchPrompt {
    final p = widget.plan;
    final isEventLinked = (p['partyEventId'] ?? p['adId'] ?? p['upcomingNightId']) != null;
    return isEventLinked &&
        (p['eventNoMatchPrompt'] == true ||
            p['eventNoMatchNotifiedAt'] != null ||
            p['metadata']?['eventNoMatchPrompt'] == true ||
            p['metadata']?['type'] == 'event_plan_no_match');
  }

  bool _isLoadingNoMatchAction = false;

  Future<void> _handleNoMatchResponse(String planId, String action) async {
    setState(() => _isLoadingNoMatchAction = true);
    try {
      final res = await ApiService.respondToEventPlanNoMatch(
        planId: planId,
        action: action,
      );
      if (!mounted) return;
      setState(() => _isLoadingNoMatchAction = false);

      if (res['success'] == true) {
        if (action == 'cancel') {
          setState(() {
            widget.plan['status'] = 'cancelled';
            widget.plan['lifecycleStatus'] = 'cancelled';
            widget.plan['isLive'] = false;
            widget.plan['eventNoMatchPrompt'] = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message']?.toString() ?? 'Plan cancelled and refunded.'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (action == 'solo') {
          setState(() {
            widget.plan['status'] = 'inactive';
            widget.plan['lifecycleStatus'] = 'completed';
            widget.plan['isSolo'] = true;
            widget.plan['paymentStatus'] = 'Converted to solo ticket';
            widget.plan['bookingId'] = res['data']?['bookingId'];
            widget.plan['ticketCode'] = res['data']?['ticketCode'];
            widget.plan['eventNoMatchPrompt'] = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message']?.toString() ?? 'Solo ticket confirmed!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() {
            widget.plan['eventNoMatchPrompt'] = false;
            widget.plan['eventNoMatchNotifiedAt'] = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message']?.toString() ?? 'Your plan will remain active.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        ApiService.notifyFeedNeedsRefresh();
        await _refreshPlanDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'Could not process request.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingNoMatchAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildNoMatchActionPromptSection() {
    final cleanPlanId = widget.plan['id']?.toString() ?? '';
    final venue = _extractVenue(widget.plan);
    final venueName = venue['name']?.toString() ?? 'the venue';
    final bool isSelfPay = (widget.plan['paymentType'] ?? '').toString().toLowerCase() == 'self_pay';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_rounded, color: Color(0xFFD97706), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No Partner Joined Yet',
                  style: TextStyle(
                    color: Color(0xFFD97706),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nobody has joined your plan at $venueName yet. You can keep waiting for someone, convert your ticket to go solo, or cancel for a full refund.',
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoadingNoMatchAction
                      ? null
                      : () => _handleNoMatchResponse(cleanPlanId, 'keep'),
                  icon: const Icon(Icons.schedule_rounded, size: 16),
                  label: const Text('KEEP WAITING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4B5563),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoadingNoMatchAction
                      ? null
                      : () => _handleNoMatchResponse(cleanPlanId, 'solo'),
                  icon: const Icon(Icons.person_rounded, size: 16),
                  label: Text(
                    isSelfPay ? 'GO SOLO (+REFUND)' : 'GO SOLO',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoadingNoMatchAction
                      ? null
                      : () => _handleNoMatchResponse(cleanPlanId, 'cancel'),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('CANCEL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _isExpired {
    final plan = widget.plan;
    if (plan['isExpired'] == true) return true;
    final status = (plan['status'] ?? '').toString().toLowerCase();
    final lifecycleStatus = (plan['lifecycleStatus'] ?? plan['lifecycle_status'] ?? '').toString().toLowerCase();

    if (status == 'expired' || lifecycleStatus == 'expired' || lifecycleStatus == 'payment_expired') return true;

    final rawDateTime = plan['planDateTime'] ??
        plan['eventDateTime'] ??
        plan['planDate'] ??
        plan['partyDate'] ??
        plan['bookingDate'];

    if (rawDateTime != null) {
      try {
        final planTime = DateTime.parse(rawDateTime.toString()).toLocal();
        // Only treat as expired after a 4-hour grace window (matches live_feed_screen.dart).
        if (DateTime.now().isAfter(planTime.add(const Duration(hours: 4)))) {
          return true;
        }
      } catch (_) {}
    }

    final rawDeadline = plan['paymentDeadlineAt'] ?? plan['paymentTimeoutAt'];
    if (rawDeadline != null && (_requestStatus == 'accepted' || _requestStatus == 'payment_pending')) {
      try {
        final deadline = DateTime.parse(rawDeadline.toString()).toLocal();
        if (deadline.isBefore(DateTime.now())) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Widget _expiredBanner() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_off_rounded, color: Colors.grey, size: 20),
              SizedBox(width: 10),
              Text(
                'THIS EVENT HAS EXPIRED',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _partnerAlreadySelectedBanner() {
    final host = _extractHost(widget.plan);
    final String hostName = _extractHostName(host, widget.plan);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFECACA)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Text(
                      'NO LONGER AVAILABLE',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Party Plan Unavailable',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This Party Plan is no longer available.\n\n$hostName has joined with another partner.\n\nFind another Party Plan or create your own.',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PlanHubScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LunaraTheme.electricViolet,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Find Another Plan',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PlanHubScreen(autoShowCreatePlan: true)),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Create Your Own',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRequestsSection() {
    if (_pendingRequests.isEmpty || (widget.plan['matchedRequestId'] != null && widget.plan['matchedRequestId'].toString().isNotEmpty)) {
      return const SizedBox.shrink();
    }

    final isPrivatePlan = widget.plan['type'] == 'PRIVATE' ||
        widget.plan['isPrivate'] == true ||
        widget.plan['privacy'] == 'PRIVATE' ||
        _pendingRequests.every((r) {
          final rType = r['requestType']?.toString().toUpperCase();
          final rIsInvite = r['isInvite'] == true;
          return rType == 'PRIVATE_INVITE' || rIsInvite;
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPrivatePlan ? Icons.mark_email_read_rounded : Icons.people_alt_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isPrivatePlan
                      ? 'PRIVATELY INVITED (${_pendingRequests.length})'
                      : 'JOIN REQUESTS (${_pendingRequests.length})',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _pendingRequests.length,
            separatorBuilder: (context, index) => const Divider(color: Color(0xFFF1F5F9), height: 20),
            itemBuilder: (context, index) {
              final req = _pendingRequests[index];
              final reqUser = (req['requester'] is Map)
                  ? Map<String, dynamic>.from(req['requester'])
                  : (req['user'] is Map ? Map<String, dynamic>.from(req['user']) : <String, dynamic>{});
              final reqUserName = '${reqUser["firstName"] ?? "User"} ${reqUser["lastName"] ?? ""}'.trim();
              final reqId = req['id']?.toString() ?? '';
              final userBio = reqUser['profile']?['bio']?.toString() ?? reqUser['bio']?.toString() ?? '';
              final foodPref = req['foodPreference']?.toString() ?? reqUser['foodPreference']?.toString();
              final drinkPref = req['drinkPreference']?.toString() ?? reqUser['drinkPreference']?.toString();

              final bool isInvite = req['isInvite'] == true ||
                  req['requestType']?.toString().toUpperCase() == 'PRIVATE_INVITE' ||
                  isPrivatePlan ||
                  (widget.plan['selectedUsers'] is List &&
                      (widget.plan['selectedUsers'] as List)
                          .contains(reqUser['id']?.toString() ?? req['requesterId']?.toString()));

              final reqStatus = (req['status'] ?? req['lifecycleStatus'] ?? 'PENDING').toString().toUpperCase();
              final isAccepted = reqStatus == 'ACCEPTED' || reqStatus == 'USER_ACCEPTED';
              final isRejected = reqStatus == 'REJECTED' || reqStatus == 'DECLINED';
              final isCancelled = reqStatus == 'CANCELLED';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LunaraProfileImage(
                        userData: reqUser,
                        radius: 22,
                        showGradientBorder: true,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reqUserName.isNotEmpty ? reqUserName : 'Lunara Member',
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (userBio.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  userBio,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (foodPref != null || drinkPref != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Food: ${foodPref ?? "Any"} • Drink: ${drinkPref ?? "Any"}',
                                  style: const TextStyle(
                                    color: Color(0xFF7C3AED),
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
                  const SizedBox(height: 10),
                  if (isAccepted)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Request Accepted • Awaiting Deposit',
                            style: TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isRejected)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Request Declined',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isCancelled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.block_rounded, color: Color(0xFF64748B), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Invitation Cancelled',
                            style: TextStyle(
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isInvite)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _processingReqIds.contains(reqId)
                            ? null
                            : () => _handleCancelPrivateRequest(reqId),
                        icon: _processingReqIds.contains(reqId)
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                              )
                            : const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFDC2626)),
                        label: Text(
                          _processingReqIds.contains(reqId) ? 'Cancelling...' : 'Cancel Private Request',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          backgroundColor: const Color(0xFFFEF2F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _processingReqIds.contains(reqId)
                                ? null
                                : () => _handleAcceptPartyPlanRequest(reqId),
                            icon: _processingReqIds.contains(reqId)
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle_rounded, size: 15),
                            label: Text(
                              _processingReqIds.contains(reqId) ? 'Approving...' : 'Approve',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _processingReqIds.contains(reqId)
                                ? null
                                : () => _handleRejectPartyPlanRequest(reqId),
                            icon: _processingReqIds.contains(reqId)
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                                  )
                                : const Icon(Icons.cancel_rounded, size: 15, color: Color(0xFFDC2626)),
                            label: Text(
                              _processingReqIds.contains(reqId) ? 'Declining...' : 'Decline',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFDC2626)),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFECACA)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }


  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
