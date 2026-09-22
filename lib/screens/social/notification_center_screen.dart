import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/push_notification_service.dart';
import '../../models/user.dart';
import '../profile/vip_membership_screen.dart';
import '../profile/profile_screen.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/top_notification_banner.dart';
import '../../widgets/upcoming_night_invite_dialog.dart';
import 'live_feed_screen.dart';
import 'chat_screen.dart';
import 'party_plan_ticket_screen.dart';
import 'party_plan_detail_screen.dart';
import 'strangers_meet_ticket_screen.dart';
import 'strangers_meet_payment_screen.dart';
import '../../models/strangers_meet_request.dart';
import 'large_party_ticket_screen.dart';
import '../discovery/digital_ticket_screen.dart';
import '../profile/lunara_wallet_screen.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/lunara_countdown_button.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../widgets/lunara_cached_image.dart';
import '../../widgets/party_safety_check_dialog.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  // Primary Tabs: 0: ALL, 1: REQUESTS, 2: ACTIVITY
  int _selectedPrimaryTab = 0;

  // Secondary Filter: 0: ALL, 1: PARTNER REQUESTS, 2: INTERESTS, 3: BOOKINGS, 4: TICKETS, 5: MESSAGES, 6: OTHER
  int _selectedCategoryFilter = 0;

  bool _isLoading = true;
  bool _isMarkingAllRead = false;
  List<dynamic> _notifications = [];
  final Set<String> _loadingActionKeys = {};
  final Set<String> _navigatingCardIds = {};

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    ApiService.addSocketListener('notification_created', _onSocketNotification);
    ApiService.addSocketListener(
      'notification_received',
      _onSocketNotification,
    );
    ApiService.addSocketListener(
      'notification_updated',
      _onSocketNotificationUpdated,
    );
  }

  @override
  void dispose() {
    ApiService.removeSocketListener(
      'notification_created',
      _onSocketNotification,
    );
    ApiService.removeSocketListener(
      'notification_received',
      _onSocketNotification,
    );
    ApiService.removeSocketListener(
      'notification_updated',
      _onSocketNotificationUpdated,
    );
    super.dispose();
  }

  void _onSocketNotification(dynamic data) {
    if (!mounted || data == null) return;
    final Map<String, dynamic> rawMap = data is Map
        ? Map<String, dynamic>.from(data)
        : {};
    final Map<String, dynamic> notifMap = rawMap['notification'] is Map
        ? Map<String, dynamic>.from(rawMap['notification'])
        : rawMap;

    final String recipientId =
        (notifMap['recipientUserId'] ??
                notifMap['recipientId'] ??
                notifMap['userId'] ??
                '')
            .toString();
    final String currentUid = ApiService.currentUserId ?? '';
    if (recipientId.isNotEmpty &&
        currentUid.isNotEmpty &&
        recipientId != currentUid) {
      return;
    }

    TopNotificationBanner.show(
      title: notifMap['title'] ?? 'New Notification',
      body: notifMap['body'] ?? '',
      data: notifMap['data'] is Map
          ? Map<String, dynamic>.from(notifMap['data'])
          : (notifMap['metadata'] is Map ? Map<String, dynamic>.from(notifMap['metadata']) : notifMap),
      senderData: notifMap['sender'] is Map
          ? Map<String, dynamic>.from(notifMap['sender'])
          : null,
    );

    setState(() {
      _notifications.insert(0, notifMap);
    });
  }

  void _onSocketNotificationUpdated(dynamic data) {
    if (!mounted || data == null) return;
    final Map<String, dynamic> updatedNotif = data is Map
        ? Map<String, dynamic>.from(data)
        : {};
    final id =
        updatedNotif['id']?.toString() ??
        updatedNotif['notification']?['id']?.toString();
    if (id == null) return;

    setState(() {
      final index = _notifications.indexWhere((n) => n['id']?.toString() == id);
      if (index != -1) {
        _notifications[index] = updatedNotif['notification'] ?? updatedNotif;
      }
    });
  }

  Future<void> _fetchNotifications() async {
    final currentUid = ApiService.currentUserId ?? '';
    if (currentUid.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await ApiService.get(
        '/api/mobile/user/notifications?userId=$currentUid',
      );
      if (response.statusCode == 200 && mounted) {
        final bodyData = jsonDecode(response.body);
        if (bodyData != null && bodyData['data'] is List) {
          final fetchedList = List<dynamic>.from(bodyData['data']);

          debugPrint('========== NOTIFICATION API DEBUG ==========');
          debugPrint('TOTAL NOTIFICATIONS = ${fetchedList.length}');
          for (final n in fetchedList) {
            if (n is Map) {
              final data = n['data'];
              debugPrint(
                'NOTIFICATION: '
                'id=${n['id']} '
                'type=${n['type']} '
                'title=${n['title']} '
                'body=${n['body']} '
                'dataType=${data.runtimeType} '
                'data=$data',
              );
              if ((n['body'] ?? '').toString().toLowerCase().contains(
                'pay deposit',
              )) {
                debugPrint('*** PAY DEPOSIT API NOTIFICATION FOUND ***');
                debugPrint('FULL ITEM = $n');
              }
            }
          }

          setState(() {
            _notifications = fetchedList;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(dynamic item) async {
    final notifId = item['id']?.toString();
    final currentUid = ApiService.currentUserId ?? '';

    if (notifId != null && notifId.isNotEmpty && currentUid.isNotEmpty) {
      try {
        await ApiService.patch(
          '/api/mobile/user/notifications/$notifId/read?userId=$currentUid',
          body: {},
        );
      } catch (e) {
        debugPrint('Error marking notification as read: $e');
      }
    }

    if (mounted) {
      setState(() {
        item['read'] = true;
        item['isRead'] = true;
      });
    }

    final Map<String, dynamic> payloadData = {};
    if (item is Map) {
      payloadData.addAll(Map<String, dynamic>.from(item));
      if (item['data'] is Map) {
        payloadData.addAll(Map<String, dynamic>.from(item['data']));
      }
      if (item['metadata'] is Map) {
        payloadData.addAll(Map<String, dynamic>.from(item['metadata']));
      }
      if (!payloadData.containsKey('type') && item['eventType'] != null) {
        payloadData['type'] = item['eventType'];
      }
      if (!payloadData.containsKey('requestId') && item['entityId'] != null) {
        payloadData['requestId'] = item['entityId'];
      }
    }
    PushNotificationService.navigateFromPayload(payloadData);
  }

  Future<void> _markAllAsRead() async {
    final currentUid = ApiService.currentUserId ?? '';
    if (currentUid.isEmpty || _isMarkingAllRead) return;

    setState(() => _isMarkingAllRead = true);

    try {
      await ApiService.markAllNotificationsAsRead();
      if (mounted) {
        setState(() {
          for (var item in _notifications) {
            item['read'] = true;
            item['isRead'] = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read ✓'),
            backgroundColor: LunaraTheme.electricViolet,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    } finally {
      if (mounted) {
        setState(() => _isMarkingAllRead = false);
      }
    }
  }

  Future<void> _handleNotificationAction(dynamic item, String action) async {
    final notifId = item['id']?.toString();
    final currentUid = ApiService.currentUserId ?? '';

    if (notifId == null || notifId.isEmpty || currentUid.isEmpty) return;

    final actionKey = '$notifId:$action';
    if (_loadingActionKeys.contains(actionKey)) return;

    setState(() {
      _loadingActionKeys.add(actionKey);
    });

    // Optimistic UI update
    setState(() {
      item['read'] = true;
      item['isRead'] = true;
      item['metadata'] = {
        ...(item['metadata'] is Map ? item['metadata'] : {}),
        'status': 'ACTIONED',
        'actionExecuted': action,
      };
    });

    try {
      final payloadData = item['data'] is Map
          ? Map<String, dynamic>.from(item['data'])
          : (item['metadata'] is Map
                ? Map<String, dynamic>.from(item['metadata'])
                : <String, dynamic>{});
      final requestId =
          payloadData['requestId']?.toString() ?? item['entityId']?.toString();
      final entityType = (item['entityType'] ?? payloadData['type'] ?? '')
          .toString();

      final matchId = payloadData['matchId']?.toString() ??
          payloadData['nightId']?.toString() ??
          requestId;

      if ((entityType == 'night_partner' ||
              entityType == 'NightPartnerRequest' ||
              entityType.contains('PARTNER_REQUEST')) &&
          requestId != null &&
          requestId.isNotEmpty &&
          (action.toUpperCase() == 'ACCEPT' || action.toUpperCase() == 'DECLINE')) {
        final act = action.toUpperCase() == 'ACCEPT' ? 'accept' : 'decline';
        await ApiService.respondToNightPartnerRequest(
          requestId: requestId,
          action: act,
        );
      }

      if ((action == 'ACCEPT_CANCELLATION' ||
              action == 'REJECT_CANCELLATION' ||
              action == 'DECLINE_CANCELLATION') &&
          matchId != null &&
          matchId.isNotEmpty) {
        final cancAction = action == 'ACCEPT_CANCELLATION' ? 'approve' : 'reject';
        await ApiService.cancelUpcomingNight(
          targetId: matchId,
          action: cancAction,
        );
      }

      final response = await ApiService.post(
        '/api/mobile/notifications/$notifId/action',
        body: {'action': action, 'userId': currentUid},
      );

      if (response.statusCode == 200 && mounted) {
        final isCancAccept = action == 'ACCEPT_CANCELLATION';
        final isCancReject = action == 'REJECT_CANCELLATION' || action == 'DECLINE_CANCELLATION';
        final isAccept = action.toUpperCase() == 'ACCEPT';

        String snackMsg = 'Action completed';
        Color snackColor = Colors.green;
        if (isCancAccept) {
          snackMsg = '💳 Cancellation approved! Refund added to your wallet.';
          snackColor = Colors.green;
        } else if (isCancReject) {
          snackMsg = 'Cancellation declined. Upcoming Night remains confirmed!';
          snackColor = LunaraTheme.electricViolet;
        } else if (isAccept) {
          snackMsg = '🎉 Invite Accepted!';
          snackColor = Colors.green;
        } else {
          snackMsg = 'Invite Declined';
          snackColor = Colors.grey[800]!;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackMsg),
            backgroundColor: snackColor,
          ),
        );
        _fetchNotifications();
      }
    } catch (e) {
      debugPrint('Error processing action: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingActionKeys.remove(actionKey);
        });
      }
    }
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear Notifications?',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This will clear your notification view. Critical transactional records remain preserved in history.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'CLEAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _clearAllNotifications();
    }
  }

  Future<void> _clearAllNotifications() async {
    final currentUid = ApiService.currentUserId ?? '';
    if (currentUid.isEmpty) return;

    final backup = List<dynamic>.from(_notifications);
    setState(() {
      _notifications.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notifications cleared'),
        backgroundColor: LunaraTheme.electricViolet,
      ),
    );

    try {
      final response = await ApiService.post(
        '/api/mobile/notifications/clear-all',
        body: {'userId': currentUid},
      );
      if (response.statusCode != 200 && mounted) {
        setState(() {
          _notifications.addAll(backup);
        });
      }
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
      if (mounted) {
        setState(() {
          _notifications.addAll(backup);
        });
      }
    }
  }

  bool _isProcessingPayment = false;

  void _startRazorpayDirectPayment({
    required String requestId,
    required String venueName,
    String? orderId,
    double depositAmount = 99.0,
    required VoidCallback onSuccess,
  }) async {
    if (_isProcessingPayment) return;
    setState(() => _isProcessingPayment = true);

    try {
      String currentOrderId = (orderId ?? '').trim();
      String razorpayKey = 'rzp_test_123';

      if (currentOrderId.isEmpty) {
        final initRes = await ApiService.initiateJoinerPayment(requestId);
        if (initRes != null && initRes['success'] == true) {
          currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
          if (initRes['razorpayKeyId'] != null &&
              initRes['razorpayKeyId'].toString().isNotEmpty) {
            razorpayKey = initRes['razorpayKeyId'].toString();
          }
        }
      }

      final isMock =
          razorpayKey == 'rzp_test_123' ||
          razorpayKey == 'your_razorpay_key_id' ||
          currentOrderId.isEmpty ||
          currentOrderId.startsWith('order_mock_') ||
          currentOrderId.startsWith('mock_') ||
          currentOrderId.startsWith('pay_direct_');

      if (isMock) {
        final ordId = currentOrderId.isNotEmpty
            ? currentOrderId
            : 'order_mock_direct';
        final confirmRes = await ApiService.post(
          '/api/mobile/party-plans/requests/$requestId/joiner-pay',
          body: {
            'userId': ApiService.currentUserId ?? '',
            'razorpay_order_id': ordId,
            'razorpay_payment_id':
                'pay_direct_${DateTime.now().millisecondsSinceEpoch}',
            'razorpay_signature': 'mock_signature',
          },
        );
        if (mounted) setState(() => _isProcessingPayment = false);
        if (confirmRes.statusCode == 200 && mounted) {
          onSuccess();
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
            msg =
                b['message'] ??
                b['error'] ??
                'Server status ${confirmRes.statusCode}';
          } catch (_) {
            msg = 'Server status ${confirmRes.statusCode}';
          }
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

      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
        PaymentSuccessResponse response,
      ) async {
        final confirmRes = await ApiService.post(
          '/api/mobile/party-plans/requests/$requestId/joiner-pay',
          body: {
            'userId': ApiService.currentUserId ?? '',
            'razorpay_order_id':
                response.orderId ??
                (currentOrderId.isNotEmpty
                    ? currentOrderId
                    : 'order_rzp_${DateTime.now().millisecondsSinceEpoch}'),
            'razorpay_payment_id':
                response.paymentId ??
                'pay_${DateTime.now().millisecondsSinceEpoch}',
            'razorpay_signature': response.signature ?? 'signature',
          },
        );
        razorpay.clear();
        if (mounted) setState(() => _isProcessingPayment = false);
        if (confirmRes.statusCode == 200 && mounted) {
          onSuccess();
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

      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (
        PaymentFailureResponse response,
      ) {
        razorpay.clear();
        if (mounted) setState(() => _isProcessingPayment = false);
        if (mounted) {
          final errText =
              (response.message != null &&
                  response.message!.isNotEmpty &&
                  response.message != 'Payment Failed')
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

      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (
        ExternalWalletResponse response,
      ) {
        razorpay.clear();
        if (mounted) setState(() => _isProcessingPayment = false);
      });

      final options = <String, dynamic>{
        'key': razorpayKey,
        'amount': (depositAmount * 100).round(),
        'name': 'Lunara Party Deposit',
        'description': 'Safety deposit for Party Plan at $venueName',
        if (currentOrderId.isNotEmpty) 'order_id': currentOrderId,
        'prefill': {'contact': '9999999999', 'email': 'user@lunara.app'},
        'theme': {'color': '#7C3AED'},
      };

      try {
        razorpay.open(options);
      } catch (e) {
        debugPrint('Error opening Razorpay: $e');
        if (mounted) setState(() => _isProcessingPayment = false);
      }
    } catch (e) {
      debugPrint('Error initiating joiner deposit payment: $e');
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  Future<void> _startHostRazorpayDirectPayment({
    required String partyPlanId,
    required String venueName,
    required String orderId,
    required double depositAmount,
    required Future<void> Function() onSuccess,
  }) async {
    if (_isProcessingPayment) return;
    setState(() => _isProcessingPayment = true);

    String cleanPlanId = partyPlanId.trim();
    if (cleanPlanId.startsWith('party_plan_timeline_')) {
      cleanPlanId = cleanPlanId.replaceFirst('party_plan_timeline_', '');
    }
    if (cleanPlanId.startsWith('pp_')) {
      cleanPlanId = cleanPlanId.replaceFirst('pp_', '');
    }

    debugPrint(
      '[HOST_PAYMENT_START] Host Pay Deposit clicked: cleanPlanId=$cleanPlanId, venueName=$venueName, orderId=$orderId, depositAmount=$depositAmount',
    );

    try {
      String currentOrderId = orderId.trim();
      String razorpayKey = 'rzp_test_123';

      if (currentOrderId.isEmpty ||
          (!currentOrderId.startsWith('order_mock_') &&
              !currentOrderId.startsWith('mock_') &&
              !currentOrderId.startsWith('pay_direct_') &&
              currentOrderId.length < 10)) {
        debugPrint(
          '[HOST_ORDER_CREATE] Creating Razorpay order via initiateHostPayment',
        );
        final initRes = await ApiService.initiateHostPayment(cleanPlanId);
        debugPrint(
          '[HOST_ORDER_RESPONSE] Order API response received: $initRes',
        );
        if (initRes != null && initRes['success'] == true) {
          currentOrderId = (initRes['razorpayOrderId'] ?? '').toString();
          if (initRes['razorpayKeyId'] != null &&
              initRes['razorpayKeyId'].toString().isNotEmpty) {
            razorpayKey = initRes['razorpayKeyId'].toString();
          }
        }
      }

      debugPrint(
        '[HOST_ORDER_RESPONSE] Razorpay order ID received: orderId=$currentOrderId, keyId=$razorpayKey',
      );

      late Razorpay razorpay;
      razorpay = Razorpay();

      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
        PaymentSuccessResponse response,
      ) async {
        final pId = response.paymentId ?? '';
        final oId = response.orderId ?? currentOrderId;
        final sig = response.signature ?? '';

        debugPrint(
          '[PAYMENT-06] Razorpay success callback: '
          'paymentId=$pId, orderId=$oId, signature=$sig',
        );

        debugPrint('[PAYMENT-08] Verifying payment with backend');
        final confirmRes = await ApiService.post(
          '/api/mobile/party-plans/$cleanPlanId/host-pay',
          body: {
            'userId': ApiService.currentUserId ?? '',
            'razorpay_order_id': oId,
            'razorpay_payment_id': pId,
            'razorpay_signature': sig,
          },
        );

        debugPrint(
          '[PAYMENT-09] Verification response: statusCode=${confirmRes.statusCode}, body=${confirmRes.body}',
        );

        razorpay.clear();
        if (mounted) setState(() => _isProcessingPayment = false);
        if (confirmRes.statusCode == 200 && mounted) {
          debugPrint('[PAYMENT-10] Deposit status updated successfully');
          await onSuccess();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '🎉 Host Safety Deposit Paid! Your plan is fully activated.',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else if (mounted) {
          String msg = 'Payment Confirmation Failed';
          try {
            final b = jsonDecode(confirmRes.body);
            msg = b['message'] ?? b['error'] ?? msg;
          } catch (_) {}
          if (msg == 'Payment Failed') {
            msg = 'Verification failed (Status ${confirmRes.statusCode})';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $msg'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });

      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (
        PaymentFailureResponse response,
      ) {
        debugPrint(
          '[PAYMENT-07] Razorpay error callback: code=${response.code}, message=${response.message}',
        );
        razorpay.clear();
        if (mounted) setState(() => _isProcessingPayment = false);
        if (mounted) {
          String errText =
              response.message ?? 'Payment process cancelled or failed';
          if (errText.isEmpty || errText == 'Payment Failed') {
            if (response.code == Razorpay.PAYMENT_CANCELLED) {
              errText = 'Payment cancelled by user';
            } else {
              errText = 'Payment error (code ${response.code})';
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Failed: $errText'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });

      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (
        ExternalWalletResponse response,
      ) {
        razorpay.clear();
        if (mounted) setState(() => _isProcessingPayment = false);
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

      debugPrint(
        '[PAYMENT-05] Opening Razorpay checkout: key=$razorpayKey, amount=${options['amount']}, orderId=$currentOrderId',
      );

      try {
        razorpay.open(options);
      } catch (e) {
        debugPrint('Error opening Razorpay for Host Payment: $e');
        if (mounted) setState(() => _isProcessingPayment = false);
      }
    } catch (e) {
      debugPrint('Error initiating host deposit payment: $e');
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  // ── Tab & Category Filter Logic ──────────────────────────────────────────────
  List<dynamic> get _filteredNotifications {
    var rawList = _notifications.where((item) {
      if (item is Map) {
        final body = (item['body'] ?? item['currentStatus'] ?? '')
            .toString()
            .toLowerCase();
        final title = (item['title'] ?? '').toString().toLowerCase();
        if (body.contains('waiting other user') ||
            title.contains('waiting other user') ||
            body == 'waiting other user') {
          return false;
        }
      }
      return true;
    }).toList();

    // Universal Entity Deduplication: Only 1 consolidated card per plan/booking/event showing latest status
    final Map<String, dynamic> entityMap = {};
    final List<dynamic> deduplicatedList = [];

    for (final item in rawList) {
      if (item is! Map) {
        deduplicatedList.add(item);
        continue;
      }
      final data = item['data'] is Map
          ? item['data']
          : (item['metadata'] is Map ? item['metadata'] : {});

      final itemId = item['id']?.toString() ?? '';

      // Extract specific identifiers for grouping
      final partyPlanId =
          data['partyPlanId']?.toString() ??
          data['planId']?.toString() ??
          (item['entityType'] == 'party_plan'
              ? item['entityId']?.toString()
              : null) ??
          (itemId.startsWith('party_plan_timeline_')
              ? itemId.replaceFirst('party_plan_timeline_', '')
              : null);

      final groupPartyId =
          data['groupPartyId']?.toString() ??
          data['partyId']?.toString() ??
          data['groupId']?.toString() ??
          (item['entityType'] == 'group_party' || item['entityType'] == 'GroupParty'
              ? item['entityId']?.toString()
              : null) ??
          (itemId.startsWith('group_party_timeline_')
              ? itemId.replaceFirst('group_party_timeline_', '')
              : (itemId.startsWith('group_party_')
                  ? itemId.replaceFirst('group_party_', '')
                  : null));

      final meetId =
          data['meetId']?.toString() ??
          data['strangersMeetId']?.toString() ??
          (item['entityType'] == 'strangers_meet'
              ? item['entityId']?.toString()
              : null) ??
          (itemId.startsWith('strangers_meet_timeline_')
              ? itemId.replaceFirst('strangers_meet_timeline_', '')
              : null);

      final bookingId =
          data['bookingId']?.toString() ??
          (item['entityType'] == 'booking' || item['entityType'] == 'Booking'
              ? item['entityId']?.toString()
              : null) ??
          (itemId.startsWith('large_party_timeline_')
              ? itemId.replaceFirst('large_party_timeline_', '')
              : (itemId.startsWith('solo_booking_')
                  ? itemId.replaceFirst('solo_booking_', '')
                  : null));

      final requestId =
          data['requestId']?.toString() ?? item['entityId']?.toString();

      final groupKey = groupPartyId != null && groupPartyId.isNotEmpty
          ? 'group_$groupPartyId'
          : (partyPlanId != null && partyPlanId.isNotEmpty
                ? 'party_$partyPlanId'
                : (meetId != null && meetId.isNotEmpty
                      ? 'meet_$meetId'
                      : (bookingId != null && bookingId.isNotEmpty
                            ? 'booking_$bookingId'
                            : (requestId != null && requestId.isNotEmpty
                                  ? 'req_$requestId'
                                  : null))));

      if (groupKey != null) {
        if (!entityMap.containsKey(groupKey)) {
          entityMap[groupKey] = item;
          deduplicatedList.add(item);
        } else {
          // Replace existing raw notification with dynamic enriched timeline card if available
          final existingItem = entityMap[groupKey];
          final isCurrentTimeline = itemId.contains('_timeline_') || (item['type']?.toString().endsWith('_timeline') == true);
          final isExistingTimeline = (existingItem is Map) && ((existingItem['id']?.toString().contains('_timeline_') == true) || (existingItem['type']?.toString().endsWith('_timeline') == true));

          final currentCancelStatus = (data['cancellationStatus'] ?? item['cancellationStatus'] ?? '').toString().toLowerCase();
          final currentGenStatus = (data['status'] ?? item['status'] ?? '').toString().toLowerCase();
          final isCurrentCancelled = currentCancelStatus == 'cancelled' ||
              currentCancelStatus == 'approved' ||
              currentGenStatus == 'cancelled' ||
              currentGenStatus == 'declined' ||
              item['category'] == 'cancelled' ||
              item['category'] == 'cancellation' ||
              item['eventType']?.toString().toUpperCase().contains('CANCEL') == true ||
              (item['title']?.toString().toLowerCase().contains('cancel') ?? false) ||
              (item['body']?.toString().toLowerCase().contains('cancel') ?? false);

          if (isCurrentCancelled) {
            entityMap[groupKey] = item;
            final idx = deduplicatedList.indexOf(existingItem);
            if (idx != -1) {
              deduplicatedList[idx] = item;
            }
          } else if (isCurrentTimeline && !isExistingTimeline) {
            final idx = deduplicatedList.indexOf(existingItem);
            if (idx != -1) {
              deduplicatedList[idx] = item;
              entityMap[groupKey] = item;
            }
          } else if (groupKey.startsWith('party_')) {
          // STEP 13: ACTIVE PAY DEPOSIT > OLD/EXPIRED PARTY PLAN UPDATE
          final existingItem = entityMap[groupKey];
          final existingData =
              existingItem is Map && existingItem['data'] is Map
              ? Map<String, dynamic>.from(existingItem['data'])
              : <String, dynamic>{};
          final currentData = item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : <String, dynamic>{};

          final currentPrimaryAction = (currentData['primaryAction'] ?? '')
              .toString()
              .toLowerCase();
          final currentJoinerStatus = (currentData['joinerPaymentStatus'] ?? '')
              .toString()
              .toLowerCase();
          final currentLifecycle = (currentData['lifecycleStatus'] ?? currentData['status'] ?? '')
              .toString()
              .toLowerCase();

          final isCurrentPaidOrConfirmed =
              currentPrimaryAction == 'open chat' ||
              currentPrimaryAction == 'chat' ||
              currentLifecycle == 'match_confirmed' ||
              currentLifecycle == 'chat_enabled' ||
              currentData['chatUnlocked'] == true ||
              currentJoinerStatus == 'paid' ||
              currentJoinerStatus == 'completed';

          final isCurrentActivePayDeposit =
              (currentPrimaryAction == 'pay deposit' ||
                  currentPrimaryAction == 'pay now') &&
              !isCurrentPaidOrConfirmed;

          final existingPrimaryAction = (existingData['primaryAction'] ?? '')
              .toString()
              .toLowerCase();
          final existingJoinerStatus =
              (existingData['joinerPaymentStatus'] ?? '')
                  .toString()
                  .toLowerCase();
          final existingLifecycle = (existingData['lifecycleStatus'] ?? existingData['status'] ?? '')
              .toString()
              .toLowerCase();

          final isExistingPaidOrConfirmed =
              existingPrimaryAction == 'open chat' ||
              existingPrimaryAction == 'chat' ||
              existingLifecycle == 'match_confirmed' ||
              existingLifecycle == 'chat_enabled' ||
              existingData['chatUnlocked'] == true ||
              existingJoinerStatus == 'paid' ||
              existingJoinerStatus == 'completed';

          final isExistingActivePayDeposit =
              (existingPrimaryAction == 'pay deposit' ||
                  existingPrimaryAction == 'pay now') &&
              !isExistingPaidOrConfirmed;

          if ((isCurrentActivePayDeposit && !isExistingActivePayDeposit) ||
              (isCurrentPaidOrConfirmed && !isExistingPaidOrConfirmed)) {
            entityMap[groupKey] = item;
            final idx = deduplicatedList.indexOf(existingItem);
            if (idx != -1) {
              deduplicatedList[idx] = item;
            }
          }
        } else if (groupKey.startsWith('meet_')) {
          final existingItem = entityMap[groupKey];
          final existingData =
              existingItem is Map && existingItem['data'] is Map
              ? Map<String, dynamic>.from(existingItem['data'])
              : (existingItem is Map && existingItem['metadata'] is Map
                  ? Map<String, dynamic>.from(existingItem['metadata'])
                  : <String, dynamic>{});
          final currentData = item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : (item['metadata'] is Map
                  ? Map<String, dynamic>.from(item['metadata'])
                  : <String, dynamic>{});

          final currentPaymentStatus = (currentData['paymentStatus'] ?? currentData['joinerPaymentStatus'] ?? item['paymentStatus'] ?? '')
              .toString()
              .toLowerCase();
          final currentStatus = (currentData['status'] ?? item['status'] ?? '')
              .toString()
              .toLowerCase();
          final isCurrentPaidOrConfirmed = currentPaymentStatus == 'paid' ||
              currentPaymentStatus == 'completed' ||
              currentStatus == 'paid' ||
              currentStatus == 'confirmed' ||
              currentStatus == 'completed' ||
              item['isPaid'] == true ||
              currentData['isPaid'] == true;

          final existingPaymentStatus = (existingData['paymentStatus'] ?? existingData['joinerPaymentStatus'] ?? (existingItem is Map ? existingItem['paymentStatus'] : '') ?? '')
              .toString()
              .toLowerCase();
          final existingStatus = (existingData['status'] ?? (existingItem is Map ? existingItem['status'] : '') ?? '')
              .toString()
              .toLowerCase();
          final isExistingPaidOrConfirmed = existingPaymentStatus == 'paid' ||
              existingPaymentStatus == 'completed' ||
              existingStatus == 'paid' ||
              existingStatus == 'confirmed' ||
              existingStatus == 'completed' ||
              (existingItem is Map && existingItem['isPaid'] == true) ||
              existingData['isPaid'] == true;

          final isCurrentActivePayFee = (currentStatus == 'approved' || currentStatus == 'accepted' || currentPaymentStatus == 'pending') && !isCurrentPaidOrConfirmed;
          final isExistingActivePayFee = (existingStatus == 'approved' || existingStatus == 'accepted' || existingPaymentStatus == 'pending') && !isExistingPaidOrConfirmed;

          if ((isCurrentPaidOrConfirmed && !isExistingPaidOrConfirmed) ||
              (isCurrentActivePayFee && !isExistingActivePayFee && !isExistingPaidOrConfirmed)) {
            entityMap[groupKey] = item;
            final idx = deduplicatedList.indexOf(existingItem);
            if (idx != -1) {
              deduplicatedList[idx] = item;
            }
          }
        } else if (groupKey.startsWith('group_') || groupKey.startsWith('booking_')) {
          final existingItem = entityMap[groupKey];
          final existingData =
              existingItem is Map && existingItem['data'] is Map
              ? Map<String, dynamic>.from(existingItem['data'])
              : (existingItem is Map && existingItem['metadata'] is Map
                  ? Map<String, dynamic>.from(existingItem['metadata'])
                  : <String, dynamic>{});
          final currentData = item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : (item['metadata'] is Map
                  ? Map<String, dynamic>.from(item['metadata'])
                  : <String, dynamic>{});

          final currentPaymentStatus = (currentData['paymentStatus'] ?? currentData['status'] ?? item['paymentStatus'] ?? item['status'] ?? '')
              .toString()
              .toLowerCase();
          final isCurrentPaidOrConfirmed = currentPaymentStatus == 'paid' ||
              currentPaymentStatus == 'confirmed' ||
              currentPaymentStatus == 'completed' ||
              item['isPaid'] == true ||
              currentData['isPaid'] == true;

          final existingPaymentStatus = (existingData['paymentStatus'] ?? existingData['status'] ?? (existingItem is Map ? (existingItem['paymentStatus'] ?? existingItem['status']) : '') ?? '')
              .toString()
              .toLowerCase();
          final isExistingPaidOrConfirmed = existingPaymentStatus == 'paid' ||
              existingPaymentStatus == 'confirmed' ||
              existingPaymentStatus == 'completed' ||
              (existingItem is Map && existingItem['isPaid'] == true) ||
              existingData['isPaid'] == true;

          if (isCurrentPaidOrConfirmed && !isExistingPaidOrConfirmed) {
            entityMap[groupKey] = item;
            final idx = deduplicatedList.indexOf(existingItem);
            if (idx != -1) {
              deduplicatedList[idx] = item;
            }
          }
        }
      }
    } else {
      deduplicatedList.add(item);
    }
  }

    var list = deduplicatedList;

    // STEP 3: DEBUG _filteredNotifications
    for (final n in list) {
      if (n is Map) {
        final data = n['data'] is Map
            ? Map<String, dynamic>.from(n['data'])
            : <String, dynamic>{};

        if ((n['body'] ?? '').toString().toLowerCase().contains(
          'pay deposit',
        )) {
          debugPrint('*** PAY DEPOSIT AFTER FILTER ***');
          debugPrint('id=${n['id']}');
          debugPrint('type=${n['type']}');
          debugPrint('body=${n['body']}');
          debugPrint('partyPlanId=${data['partyPlanId']}');
          debugPrint('primaryAction=${data['primaryAction']}');
          debugPrint('hostPaymentStatus=${data['hostPaymentStatus']}');
          debugPrint('depositAmount=${data['depositAmount']}');
          debugPrint('FULL DATA=$data');
        }
      }
    }

    // 1. Primary Navigation Tab Filter
    if (_selectedPrimaryTab == 1) {
      // REQUESTS
      list = list.where((n) {
        final title = (n['title'] ?? '').toString().toLowerCase();
        final type = (n['data']?['type'] ?? n['eventType'] ?? n['id'] ?? '')
            .toString()
            .toLowerCase();
        final category = (n['category'] ?? '').toString().toLowerCase();
        return category == 'requests' ||
            title.contains('request') ||
            title.contains('interest') ||
            title.contains('invite') ||
            type.contains('request') ||
            type.contains('interest');
      }).toList();
    } else if (_selectedPrimaryTab == 2) {
      // ACTIVITY
      list = list.where((n) {
        final title = (n['title'] ?? '').toString().toLowerCase();
        final type = (n['data']?['type'] ?? n['eventType'] ?? n['id'] ?? '')
            .toString()
            .toLowerCase();
        final category = (n['category'] ?? '').toString().toLowerCase();
        return category == 'events' ||
            category == 'system' ||
            title.contains('created') ||
            title.contains('published') ||
            title.contains('joined') ||
            type.contains('created') ||
            type.contains('joined');
      }).toList();
    }

    // 2. Secondary Category Pill Filter
    if (_selectedCategoryFilter == 0) return list;

    return list.where((n) {
      final title = (n['title'] ?? '').toString().toLowerCase();
      final body = (n['body'] ?? '').toString().toLowerCase();
      final type = (n['data']?['type'] ?? n['eventType'] ?? n['id'] ?? '')
          .toString()
          .toLowerCase();
      final category = (n['category'] ?? '').toString().toLowerCase();
      final status = (n['data']?['status'] ?? n['status'] ?? '').toString().toLowerCase();
      final cancellationStatus = (n['data']?['cancellationStatus'] ?? n['cancellationStatus'] ?? '').toString().toLowerCase();

      final bool isCancelled = category == 'cancelled' ||
          category == 'cancellation' ||
          title.contains('cancel') ||
          body.contains('cancel') ||
          type.contains('cancel') ||
          status == 'cancelled' ||
          cancellationStatus == 'cancelled' ||
          cancellationStatus == 'approved' ||
          cancellationStatus == 'requested';

      if (_selectedCategoryFilter == 1) {
        // REQUESTS
        return !isCancelled && (category == 'requests' || title.contains('request') || type.contains('request'));
      } else if (_selectedCategoryFilter == 2) {
        // CANCELLED
        return isCancelled;
      } else if (_selectedCategoryFilter == 3) {
        // INTERESTS
        return !isCancelled && (title.contains('interest') || type.contains('interest'));
      } else if (_selectedCategoryFilter == 4) {
        // BOOKINGS
        return !isCancelled && (title.contains('booking') ||
            title.contains('confirm') ||
            type.contains('booking'));
      } else if (_selectedCategoryFilter == 5) {
        // TICKETS
        return !isCancelled && (title.contains('ticket') || type.contains('ticket'));
      } else if (_selectedCategoryFilter == 6) {
        // MESSAGES
        return !isCancelled && (title.contains('message') ||
            title.contains('chat') ||
            type.contains('chat'));
      } else if (_selectedCategoryFilter == 7) {
        // OTHER
        return true;
      }
      return true;
    }).toList();
  }

  Map<String, List<dynamic>> _groupNotificationsByDate(List<dynamic> items) {
    final Map<String, List<dynamic>> grouped = {
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Earlier': [],
    };

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));

    for (final item in items) {
      final rawDate = item['createdAt'] ?? item['updatedAt'];
      DateTime itemDate = now;
      if (rawDate != null) {
        try {
          itemDate = DateTime.parse(rawDate.toString()).toLocal();
        } catch (_) {}
      }

      if (itemDate.isAfter(todayStart)) {
        grouped['Today']!.add(item);
      } else if (itemDate.isAfter(yesterdayStart)) {
        grouped['Yesterday']!.add(item);
      } else if (itemDate.isAfter(weekStart)) {
        grouped['This Week']!.add(item);
      } else {
        grouped['Earlier']!.add(item);
      }
    }

    return grouped;
  }

  String _formatTimeAgo(dynamic rawDateStr) {
    if (rawDateStr == null) return '';
    DateTime dt = DateTime.now();
    try {
      dt = DateTime.parse(rawDateStr.toString()).toLocal();
    } catch (_) {
      return '';
    }

    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM dd, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotifications;
    final grouped = _groupNotificationsByDate(filtered);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'NOTIFICATIONS',
          style: TextStyle(
            fontSize: 16,
            letterSpacing: 2.5,
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          if (_isMarkingAllRead)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: LunaraTheme.electricViolet,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Mark all as read',
              icon: const Icon(
                Icons.done_all_rounded,
                color: LunaraTheme.electricViolet,
                size: 22,
              ),
              onPressed: _markAllAsRead,
            ),
          if (_notifications.isNotEmpty)
            PopupMenuButton<String>(
              enabled: !_isMarkingAllRead,
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF475569),
              ),
              color: Colors.white,
              onSelected: (val) {
                if (val == 'clear') _confirmClearAll();
                if (val == 'mark_read') _markAllAsRead();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'mark_read',
                  child: Text(
                    'Mark all as read',
                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Text(
                    'Clear notification view',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            _buildPrimaryNavigationTabs(),
            const SizedBox(height: 10),
            _buildCategoryFilterPills(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? _buildSkeletonLoader()
                  : filtered.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: LunaraTheme.electricViolet,
                      onRefresh: _fetchNotifications,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        children: [
                          for (final section in [
                            'Today',
                            'Yesterday',
                            'This Week',
                            'Earlier',
                          ])
                            if (grouped[section] != null &&
                                grouped[section]!.isNotEmpty) ...[
                              _buildSectionHeader(
                                section,
                                grouped[section]!.length,
                              ),
                              ...grouped[section]!.map(
                                (item) => _buildTypedNotificationCard(item),
                              ),
                              const SizedBox(height: 14),
                            ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Primary Navigation Tabs (ALL | REQUESTS | ACTIVITY) ───────────────────
  Widget _buildPrimaryNavigationTabs() {
    final tabs = ['ALL', 'REQUESTS', 'ACTIVITY'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final isSelected = _selectedPrimaryTab == entry.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPrimaryTab = entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? LunaraTheme.electricViolet
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF64748B),
                      fontWeight: isSelected
                          ? FontWeight.w900
                          : FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Secondary Category Pills ───────────────────────────────────────────────
  Widget _buildCategoryFilterPills() {
    final categories = [
      'All',
      'Requests',
      'Cancelled',
      'Interests',
      'Bookings',
      'Tickets',
      'Messages',
      'Other',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: categories.asMap().entries.map((entry) {
          final isSelected = _selectedCategoryFilter == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategoryFilter = entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? LunaraTheme.electricViolet : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? LunaraTheme.electricViolet
                        : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(
                              alpha: 0.25,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable Typed Card Dispatcher ─────────────────────────────────────────
  Widget _buildTypedNotificationCard(dynamic item) {
    // STEP 4: DEBUG DISPATCHER
    debugPrint('========== CARD DISPATCHER ==========');
    if (item is Map) {
      debugPrint('id=${item['id']}');
      debugPrint('title=${item['title']}');
      debugPrint('body=${item['body']}');
      debugPrint('type=${item['type']}');
      debugPrint('eventType=${item['eventType']}');
      debugPrint('data=${item['data']}');
    }

    final Map<String, dynamic> data = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item['metadata'] is Map
              ? Map<String, dynamic>.from(item['metadata'])
              : <String, dynamic>{});

    final String type =
        (item['type'] ?? item['eventType'] ?? data['type'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    final String primaryAction =
        (data['primaryAction'] ?? item['primaryAction'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    final String hostPaymentStatus =
        (data['hostPaymentStatus'] ??
                item['hostPaymentStatus'] ??
                data['paymentStatus'] ??
                item['paymentStatus'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();

    final String bodyStr = (item['body'] ?? '').toString().trim().toLowerCase();

    debugPrint(
      'DISPATCH RESULT: '
      'type=$type '
      'primaryAction=$primaryAction '
      'hostPaymentStatus=$hostPaymentStatus '
      'body=$bodyStr',
    );

    final String eventType =
        (item['eventType'] ??
                data['eventType'] ??
                data['type'] ??
                item['type'] ??
                item['actionType'] ??
                item['category'] ??
                '')
            .toString()
            .toUpperCase();

    final title = (item['title'] ?? '').toString();
    final body = (item['body'] ?? '').toString();
    final titleLower = title.toLowerCase();
    final bodyLower = body.toLowerCase();

    final bookingData = data['booking'] is Map ? Map<String, dynamic>.from(data['booking']) : <String, dynamic>{};
    final String itemStatus = (data['status'] ?? item['status'] ?? bookingData['status'] ?? '').toString().toLowerCase();
    final String itemCancelStatus = (data['cancellationStatus'] ?? item['cancellationStatus'] ?? bookingData['cancellationStatus'] ?? '').toString().toLowerCase();

    // ── STEP 1: UNIVERSAL CANCELLATION (HIGHEST PRIORITY) ─────────────────────
    final bool isItemCancelled =
        eventType.contains('CANCEL') ||
        type.contains('cancel') ||
        itemStatus == 'cancelled' ||
        itemStatus == 'declined' ||
        itemCancelStatus == 'cancelled' ||
        itemCancelStatus == 'approved' ||
        (item['category'] ?? '').toString().toLowerCase() == 'cancelled' ||
        (item['category'] ?? '').toString().toLowerCase() == 'cancellation' ||
        titleLower.contains('cancelled') ||
        titleLower.contains('cancellation') ||
        bodyLower.contains('cancelled') ||
        bodyLower.contains('cancellation') ||
        bodyLower.contains('has been cancelled') ||
        bodyLower.contains('cancelled by host') ||
        bodyLower.contains('cancelled by user') ||
        bodyLower.contains('booking cancelled') ||
        bodyLower.contains('plan cancelled');

    if (isItemCancelled) {
      if (eventType.contains('CANCELLATION_REQUEST') ||
          eventType == 'UPCOMING_NIGHT_CANCELLATION_REQUESTED' ||
          (data['actions'] is List && (data['actions'] as List).contains('ACCEPT_CANCELLATION')) ||
          titleLower.contains('cancellation request') ||
          bodyLower.contains('requested to cancel upcoming night') ||
          bodyLower.contains('requested to cancel the upcoming night')) {
        return _buildUpcomingNightCancellationRequestCard(item);
      }

      final bool isPartyPlan = data['partyPlanId'] != null ||
          data['planId'] != null ||
          item['entityType'] == 'party_plan' ||
          type.contains('party_plan') ||
          titleLower.contains('party plan') ||
          bodyLower.contains('party plan');

      if (isPartyPlan) {
        return _buildPartyPlanCancellationCard(item);
      }
      return _buildCancelledCard(item);
    }

    // STEP 5: HOST PARTY PLAN MUST HAVE HIGHEST PRIORITY
    final bool isHostPartyPlanPayment =
        (type == 'party_plan_timeline' ||
            type.contains('party_plan_timeline') ||
            type.contains('host_payment') ||
            type.contains('host_deposit')) &&
        (primaryAction == 'pay deposit' || primaryAction == 'pay now') &&
        hostPaymentStatus != 'paid' &&
        hostPaymentStatus != 'completed';

    if (isHostPartyPlanPayment) {
      debugPrint('>>> ROUTING TO _buildPartyPlanPostedCard <<<');
      return _buildPartyPlanPostedCard(item);
    }

    // STEP 6: ALSO SUPPORT BODY FALLBACK
    final bool isHostPayDepositFallback =
        bodyStr.contains('action required: pay deposit') &&
        data['partyPlanId'] != null &&
        (primaryAction == 'pay deposit' || primaryAction == 'pay now') &&
        hostPaymentStatus != 'paid' &&
        hostPaymentStatus != 'completed';

    if (isHostPayDepositFallback) {
      debugPrint('>>> ROUTING PAY DEPOSIT FALLBACK TO PARTY PLAN CARD <<<');
      return _buildPartyPlanPostedCard(item);
    }

    // ── Safety Check event routing ──────────────────────────────────
    final bool isSafetyCheck =
        eventType.contains('SAFETY_CHECK') ||
        eventType == 'PARTY_SAFETY_CHECK' ||
        type.contains('safety_check') ||
        item['entityType'] == 'PartySafetyCheck' ||
        item['actionType'] == 'safety_check' ||
        item['category'] == 'safety' ||
        (item['category'] == 'alert' && (titleLower.contains('safety') || bodyLower.contains('safe'))) ||
        titleLower.contains('safety check') ||
        titleLower.contains('has your party ended') ||
        bodyLower.contains('confirm you are safe') ||
        bodyLower.contains('safe & sound') ||
        bodyLower.contains('has your party ended');

    if (isSafetyCheck) {
      return _buildSafetyCheckCard(item);
    }

    if (eventType.contains('REJECTED') ||
        eventType.contains('DECLINED') ||
        eventType.contains('INVITE_DECLINED') ||
        titleLower.contains('declined') ||
        bodyLower.contains('was declined') ||
        bodyLower.contains('declined your private')) {
      return _buildDeclinedRequestCard(item);
    }

    if (eventType.contains('PARTY_PLAN_INVITATION') ||
        eventType.contains('PARTY_PLAN_INVITE') ||
        titleLower.contains('party plan invitation') ||
        titleLower.contains('invited you') ||
        bodyLower.contains('invited you to join')) {
      return _buildPartyPlanInvitationCard(item);
    }

    // ── Party Plan specific event types ──────────────────────────────
    if (eventType.contains('PARTY_PLAN_REQUEST_RECEIVED') ||
        titleLower.contains('new party plan request') ||
        titleLower.contains('party plan request received') ||
        (bodyLower.contains('requested to join your party plan') &&
            item['type'] == 'incoming_request')) {
      return _buildPartyPlanRequestReceivedCard(item);
    } else if (eventType.contains('PARTY_PLAN_REQUEST_ACCEPTED') ||
        eventType.contains('PARTICIPANT_PAYMENT_REQUIRED') ||
        titleLower.contains('invite accepted') ||
        titleLower.contains('accepted your request')) {
      return _buildPartyPlanRequestAcceptedCard(item);
    } else if (eventType.contains('MATCH_CONFIRMED') ||
        titleLower.contains("match confirmed") ||
        titleLower.contains("it's a match")) {
      return _buildMatchCard(item);
    } else if (eventType.contains('PARTY_PLAN_REQUEST_SENT') ||
        (titleLower.contains('request sent') && !titleLower.contains('partner'))) {
      return _buildGenericCard(item);
    } else if (eventType.contains('PARTY_PLAN') ||
        eventType.contains('PLAN_LIVE') ||
        type.contains('party_plan_timeline') ||
        titleLower.contains('party plan') ||
        titleLower.contains('plan is now live') ||
        titleLower.contains("let's party at")) {
      return _buildPartyPlanPostedCard(item);
    }

    // ── Strangers Meet specific event types ─────────────────────────
    final bool isStrangersMeetRequestReceived =
        eventType.contains('STRANGERS_MEET_REQUEST_RECEIVED') ||
        eventType.contains('STRANGER_MEET_REQUEST_RECEIVED') ||
        eventType == 'STRANGERS_MEET_REQUEST' ||
        eventType == 'STRANGER_MEET_JOIN_REQUEST' ||
        (type.contains('strangers_meet') && (type.contains('request') || bodyLower.contains('requested to join your stranger meet'))) ||
        titleLower.contains('stranger meet request') ||
        titleLower.contains('strangers meet request') ||
        bodyLower.contains('requested to join your stranger meet');

    if (isStrangersMeetRequestReceived) {
      return _buildStrangersMeetRequestReceivedCard(item);
    }

    final bool isStrangersMeetAccepted =
        eventType.contains('STRANGERS_MEET_REQUEST_ACCEPTED') ||
        eventType.contains('STRANGERS_MEET_ACCEPTED') ||
        eventType.contains('STRANGER_MEET_ACCEPTED') ||
        eventType.contains('STRANGERS_MEET_APPROVED') ||
        eventType.contains('STRANGER_MEET_APPROVED') ||
        eventType.contains('STRANGERS_MEET_JOINER_PAID') ||
        eventType.contains('STRANGERS_MEET_CONFIRMED') ||
        (type.contains('strangers_meet') && (bodyLower.contains('accepted your request') || bodyLower.contains('seat confirmed') || bodyLower.contains('pay entry fee')));

    if (isStrangersMeetAccepted) {
      return _buildStrangersMeetAcceptedCard(item);
    }

    final bool isStrangersMeetPosted =
        eventType.contains('STRANGERS_MEET') ||
        eventType.contains('STRANGER_MEET') ||
        type.contains('strangers_meet') ||
        type.contains('stranger_meet') ||
        titleLower.contains('stranger meet') ||
        titleLower.contains('strangers meet');

    if (isStrangersMeetPosted) {
      return _buildStrangersMeetPostedCard(item);
    }

    // ── Large Party / Group Party Event Types ─────────────────────────
    final bool isLargeParty =
        eventType.contains('LARGE_PARTY') ||
        eventType.contains('GROUP_PARTY') ||
        type.contains('large_party') ||
        type.contains('group_party') ||
        titleLower.contains('large party') ||
        titleLower.contains('group party') ||
        bodyLower.contains('large party') ||
        bodyLower.contains('group party');

    if (isLargeParty) {
      return _buildLargePartyCard(item);
    }
    // ── Generic & Upcoming Night Event Types ─────────────────────
    if (eventType.contains('CANCELLATION_REQUEST') ||
        eventType == 'UPCOMING_NIGHT_CANCELLATION_REQUESTED' ||
        (data['actions'] is List && (data['actions'] as List).contains('ACCEPT_CANCELLATION')) ||
        titleLower.contains('cancellation request') ||
        bodyLower.contains('requested to cancel upcoming night') ||
        bodyLower.contains('requested to cancel the upcoming night')) {
      return _buildUpcomingNightCancellationRequestCard(item);
    }

    if (eventType.contains('SUPER_LIKE') ||
        eventType.contains('SUPERLIKE') ||
        titleLower.contains('super like') ||
        titleLower.contains('super liked') ||
        bodyLower.contains('super liked') ||
        bodyLower.contains('super like')) {
      return _buildSuperLikeCard(item);
    } else if (eventType.contains('LIKE') ||
        eventType == 'LIKE' ||
        item['category'] == 'likes' ||
        type == 'like' ||
        data['action'] == 'like' ||
        titleLower.contains('liked your profile') ||
        titleLower.contains('likes your profile') ||
        bodyLower.contains('liked your profile') ||
        bodyLower.contains('likes your profile') ||
        bodyLower.contains('someone liked your profile') ||
        bodyLower.contains('someone likes your profile') ||
        item['actionType'] == 'open_vip_upgrade' ||
        item['deepLink'] == '/vip-membership') {
      return _buildLikeCard(item);
    } else if (eventType.contains('PARTNER_REQUEST') ||
        type.contains('partner_request') ||
        type.contains('upcoming_night') ||
        titleLower.contains('partner request') ||
        titleLower.contains('wants to join') ||
        bodyLower.contains('wants to join you for an upcoming night') ||
        bodyLower.contains('invited you to join for upcoming night') ||
        bodyLower.contains('partner invite')) {
      return _buildPartnerRequestCard(item);
    } else if (eventType.contains('INTEREST') ||
        titleLower.contains('interested')) {
      return _buildInterestCard(item);
    } else if (eventType.contains('REQUEST_ACCEPTED') ||
        titleLower.contains('accepted your')) {
      return _buildRequestAcceptedCard(item);
    } else if (eventType.contains('BOOKING_CONFIRMED') ||
        titleLower.contains('booking confirmed')) {
      return _buildBookingConfirmedCard(item);
    } else if (eventType.contains('TICKET') || titleLower.contains('ticket')) {
      return _buildTicketReadyCard(item);
    } else if (eventType.contains('MESSAGE') ||
        titleLower.contains('message')) {
      return _buildChatMessageCard(item);
    } else if (eventType.contains('REMINDER') ||
        titleLower.contains('starting soon')) {
      return _buildEventReminderCard(item);
    }

    if (eventType.contains('EXPIRED') ||
        titleLower.contains('completed') ||
        titleLower.contains('ended')) {
      return _buildExpiredCard(item);
    }

    return _buildGenericCard(item);
  }

  Future<void> _openUserProfile(dynamic actorData, [String? cardId]) async {
    if (actorData == null) return;
    if (cardId != null && cardId.isNotEmpty) {
      setState(() => _navigatingCardIds.add(cardId));
    }
    Map<String, dynamic> userMap = {};
    if (actorData is Map) {
      userMap = Map<String, dynamic>.from(actorData);
    } else if (actorData is String && actorData.trim().isNotEmpty) {
      userMap = {'id': actorData.trim()};
    }

    if (userMap.isEmpty) {
      if (cardId != null && cardId.isNotEmpty && mounted) {
        setState(() => _navigatingCardIds.remove(cardId));
      }
      return;
    }

    final uid =
        userMap['id']?.toString() ??
        userMap['userId']?.toString() ??
        userMap['_id']?.toString() ??
        userMap['actorUserId']?.toString() ??
        '';
    if (uid.isEmpty || uid == 'masked') {
      if (cardId != null && cardId.isNotEmpty && mounted) {
        setState(() => _navigatingCardIds.remove(cardId));
      }
      return;
    }

    final userObj = User.fromJson({
      'id': uid,
      'firstName':
          userMap['firstName'] ??
          userMap['name'] ??
          userMap['username'] ??
          'User',
      'lastName': userMap['lastName'] ?? '',
      'photos':
          userMap['photos'] ??
          (userMap['photoUrl'] != null
              ? [
                  {'url': userMap['photoUrl']},
                ]
              : []),
      'profile': userMap['profile'] ?? {},
      'bio': userMap['bio'] ?? '',
    });

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ProfileScreen(user: userObj)),
      );
    } finally {
      if (cardId != null && cardId.isNotEmpty && mounted) {
        setState(() => _navigatingCardIds.remove(cardId));
      }
    }
  }

  void _onNotificationCardTapped(dynamic item) {
    _markAsRead(item);
    if (item == null) return;
    final cardId = (item is Map ? (item['id'] ?? item['entityId'] ?? '') : '').toString();
    if (cardId.isNotEmpty) {
      setState(() {
        _navigatingCardIds.add(cardId);
      });
    }

    final payloadData = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item['metadata'] is Map
            ? Map<String, dynamic>.from(item['metadata'])
            : <String, dynamic>{});
    final type = (item['type'] ?? item['category'] ?? payloadData['type'] ?? '').toString();
    final payload = <String, dynamic>{
      'type': type,
      'category': item['category'] ?? type,
      'title': item['title'] ?? '',
      'body': item['body'] ?? '',
      ...payloadData,
    };
    final actor = item['actor'] ?? item['sender'];
    if (actor is Map) {
      payload['actor'] = Map<String, dynamic>.from(actor);
      payload['actorUserId'] = actor['id'] ?? actor['_id'];
      payload['actorName'] = '${actor['firstName'] ?? ''} ${actor['lastName'] ?? ''}'.trim();
      payload['senderId'] = actor['id'] ?? actor['_id'];
      payload['senderName'] = payload['actorName'];
      payload['senderImage'] = actor['profilePhotoUrl'] ?? actor['photoUrl'] ?? actor['image'];
    }

    final bool isMasked = payload['isMasked'] == true ||
        payload['isMasked'] == 'true' ||
        item['isMasked'] == true ||
        item['actionType'] == 'open_vip_upgrade' ||
        item['deepLink'] == '/vip-membership';
    if (isMasked) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VIPMembershipScreen()),
      ).then((_) {
        if (mounted && cardId.isNotEmpty) {
          setState(() => _navigatingCardIds.remove(cardId));
        }
      });
      return;
    }

    try {
      PushNotificationService.navigateFromPayload(payload);
    } finally {
      if (mounted && cardId.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            setState(() {
              _navigatingCardIds.remove(cardId);
            });
          }
        });
      }
    }
  }

  void _openUpcomingNightInvite(dynamic item) {
    final payloadData = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item['metadata'] is Map
              ? Map<String, dynamic>.from(item['metadata'])
              : <String, dynamic>{});
    final requestId =
        payloadData['requestId']?.toString() ??
        item['entityId']?.toString() ??
        '';
    final actor = item['actor'] ?? item['sender'];
    final venueName = payloadData['venueName']?.toString() ?? 'Venue';
    final date = payloadData['eventDate']?.toString() ?? 'Tonight';
    final time = payloadData['eventTime']?.toString() ?? '20:00';

    showDialog(
      context: context,
      builder: (_) => UpcomingNightInviteDialog(
        requestId: requestId,
        hostProfile: actor is Map ? Map<String, dynamic>.from(actor) : null,
        venueName: venueName,
        date: date,
        time: time,
        paymentMode: payloadData['paymentMode']?.toString() ?? 'SELF_PAY',
        onAccepted: () {
          _fetchNotifications();
        },
      ),
    );
  }

  // ── P1. Party Plan Posted Card (Host sees this when their plan goes live) ───
  Widget _buildPartyPlanPostedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final title = (item['title'] ?? '🎉 Your Party Plan').toString();
    final body = item['body']?.toString() ?? 'Your party plan is now live!';
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);

    final Map<String, dynamic> data = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item['metadata'] is Map
              ? Map<String, dynamic>.from(item['metadata'])
              : (item is Map
                    ? Map<String, dynamic>.from(item)
                    : <String, dynamic>{}));

    String partyPlanId =
        (data['partyPlanId'] ??
                data['planId'] ??
                data['id'] ??
                (item['entityType'] == 'party_plan'
                    ? item['entityId']
                    : null) ??
                item['id'] ??
                '')
            .toString()
            .trim();

    if (partyPlanId.startsWith('party_plan_timeline_')) {
      partyPlanId = partyPlanId.replaceFirst('party_plan_timeline_', '');
    }
    if (partyPlanId.startsWith('pp_')) {
      partyPlanId = partyPlanId.replaceFirst('pp_', '');
    }

    final String venueName = data['venueName']?.toString().trim() ?? 'Venue';

    final String primaryAction = data['primaryAction']?.toString().trim() ?? '';

    final String hostPaymentStatus = (data['hostPaymentStatus'] ?? 'unpaid')
        .toString()
        .trim()
        .toLowerCase();

    final String hostRazorpayOrderId =
        data['hostRazorpayOrderId']?.toString().trim() ?? '';

    double depositAmount = 99.0;
    final dynamic rawAmount = data['depositAmount'];
    if (rawAmount is num) {
      depositAmount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      depositAmount = double.tryParse(rawAmount.trim()) ?? 99.0;
    }

    final bool isHostPaid =
        hostPaymentStatus == 'paid' || hostPaymentStatus == 'completed';

    final String eventType =
        (item['eventType'] ??
                data['eventType'] ??
                data['type'] ??
                item['type'] ??
                item['actionType'] ??
                item['category'] ??
                '')
            .toString()
            .toUpperCase();

    // Guard: hide global discovery notifications that belong to another user's
    // party plan with no personal relationship to the current viewer.
    final String planHostId =
        (data['userId'] ?? data['hostId'] ?? '').toString().trim();
    final String currentUid = ApiService.currentUserId ?? '';
    if (planHostId.isNotEmpty &&
        currentUid.isNotEmpty &&
        planHostId != currentUid) {
      final bool hasPersonalAction = primaryAction.isNotEmpty &&
          primaryAction != 'view plan' &&
          primaryAction != 'view';
      if (!hasPersonalAction) return const SizedBox.shrink();
    }

    // STEP 16: VERIFY THE ACTUAL RENDERER
    debugPrint('>>> PARTY PLAN POSTED CARD RENDERED <<<');
    debugPrint('eventType=$eventType');
    debugPrint('partyPlanId=$partyPlanId');
    debugPrint('primaryAction=$primaryAction');
    debugPrint('hostPaymentStatus=$hostPaymentStatus');
    debugPrint('depositAmount=$depositAmount');

    // STEP 17: VERIFY BUTTON CONDITION
    debugPrint(
      'BUTTON CHECK: '
      'partyPlanId=$partyPlanId '
      'isHostPaid=$isHostPaid '
      'primaryAction=$primaryAction '
      'depositAmount=$depositAmount',
    );

    final cardId = (item['id'] ?? item['entityId'] ?? partyPlanId).toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId) || _loadingActionKeys.contains(cardId);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PARTY PLAN',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      title.isNotEmpty ? title : '🎉 Your Party Plan is Live!',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10.5,
                    ),
                  ),
                  if (isUnread) ...[
                    const SizedBox(height: 4),
                    _buildUnreadDot(),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (partyPlanId.isNotEmpty)
            Row(
              children: [
                if (!isHostPaid) ...[
                  Builder(
                    builder: (context) {
                      final payKey = 'PAY_HOST_DEPOSIT:$partyPlanId';
                      final isPaying = _loadingActionKeys.contains(payKey);
                      return Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isPaying
                              ? null
                              : () async {
                                  _markAsRead(item);
                                  if (partyPlanId.isEmpty || depositAmount <= 0) {
                                    debugPrint(
                                      'Error: Invalid partyPlanId or depositAmount for notification payment',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Payment details unavailable. Please try again later.',
                                        ),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => _loadingActionKeys.add(payKey));
                                  try {
                                    await _startHostRazorpayDirectPayment(
                                      partyPlanId: partyPlanId,
                                      venueName: venueName,
                                      orderId: hostRazorpayOrderId,
                                      depositAmount: depositAmount,
                                      onSuccess: () async {
                                        await _fetchNotifications();
                                      },
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _loadingActionKeys.remove(payKey));
                                    }
                                  }
                                },
                          icon: isPaying
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.payment_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                          label: Text(
                            isPaying
                                ? 'Processing...'
                                : 'Pay Deposit (${depositAmount.toStringAsFixed(0)})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: Color(0xFF7C3AED),
                    ),
                    label: const Text(
                      'View Plan',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7C3AED)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── P2. Party Plan Request Received Card (Host sees incoming requests) ───────
  Widget _buildPartyPlanRequestReceivedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId) || _loadingActionKeys.contains(cardId);
    final actor = item['actor'] ?? item['sender'];
    final actorName = actor is Map
        ? '${actor['firstName'] ?? ''} ${actor['lastName'] ?? ''}'.trim()
        : (item['metadata']?['requesterName']?.toString() ?? 'Someone');
    final body =
        item['body']?.toString() ??
        '$actorName requested to join your Party Plan.';
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LunaraProfileImage(
                userData: actor is Map ? Map<String, dynamic>.from(actor) : {},
                radius: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PARTY PLAN',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      actorName.isNotEmpty
                          ? '$actorName sent a request'
                          : 'New Party Plan Request',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (actor is Map)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _openUserProfile(actor),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'View Profile',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (actor is Map) const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _markAsRead(item);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                      ),
                    ).then((_) => _fetchNotifications());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'View Plan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── P3. Party Plan Request Accepted — Partner pays deposit ──────────────────
  Widget _buildPartyPlanRequestAcceptedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final body =
        item['body']?.toString() ?? 'Pay the safety deposit to lock your spot!';
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);
    final data = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'])
        : (item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : <String, dynamic>{});
    final requestId =
        data['requestId']?.toString() ?? item['entityId']?.toString() ?? '';
    final partyPlanId =
        data['partyPlanId']?.toString() ??
        data['planId']?.toString() ??
        item['entityId']?.toString() ??
        '';
    final venueName = data['venueName']?.toString() ?? 'Venue';
    double depositAmount = 99.0;
    final rawAmount =
        data['depositAmount'] ??
        item['depositAmount'] ??
        data['amount'] ??
        item['amount'];
    if (rawAmount is num) {
      depositAmount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      depositAmount = double.tryParse(rawAmount) ?? 99.0;
    }

    final currentUid = ApiService.currentUserId ?? '';
    final planHostId = (data['hostId'] ?? data['userId'] ?? item['hostId'] ?? '').toString();
    final bool isHostOfPlan = (currentUid.isNotEmpty && planHostId.isNotEmpty && currentUid == planHostId) || item['isHost'] == true;

    final String joinerPaymentStatus =
        (data['joinerPaymentStatus'] ??
                item['joinerPaymentStatus'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();

    final String hostPaymentStatus =
        (data['hostPaymentStatus'] ??
                item['hostPaymentStatus'] ??
                data['paymentStatus'] ??
                item['paymentStatus'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();

    final String lifecycleStatus =
        (data['lifecycleStatus'] ??
                item['lifecycleStatus'] ??
                data['status'] ??
                item['status'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();

    final String currentStatus =
        (data['currentStatus'] ?? item['currentStatus'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    final String primaryAction =
        (data['primaryAction'] ?? item['primaryAction'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    final bool isChatAction =
        primaryAction == 'open chat' ||
        primaryAction == 'chat' ||
        data['chatUnlocked'] == true ||
        item['chatUnlocked'] == true ||
        data['isConfirmed'] == true ||
        item['isConfirmed'] == true;

    final bool isGuestPaid =
        joinerPaymentStatus == 'paid' ||
        joinerPaymentStatus == 'completed' ||
        data['guestPaid'] == true ||
        item['guestPaid'] == true;

    final bool isMatchConfirmed =
        lifecycleStatus == 'match_confirmed' ||
        lifecycleStatus == 'chat_enabled' ||
        lifecycleStatus == 'guest_payment_completed' ||
        lifecycleStatus == 'completed' ||
        lifecycleStatus == 'confirmed' ||
        currentStatus.contains('match confirmed') ||
        currentStatus.contains('completed') ||
        (isGuestPaid && (hostPaymentStatus == 'paid' || hostPaymentStatus.isEmpty)) ||
        isChatAction;

    final actor = item['actor'] ?? item['sender'] ?? item['actorUser'];
    final actorId =
        (actor is Map ? (actor['id'] ?? actor['userId']) : null)?.toString() ??
        '';
    final actorName =
        (actor is Map
                ? (actor['firstName'] ?? actor['name'] ?? 'Partner')
                : 'Partner')
            .toString();

    final bool isCardLoading = _navigatingCardIds.contains(cardId) || _loadingActionKeys.contains(cardId);

    // If viewer is host and match is not yet confirmed by guest payment:
    if (isHostOfPlan && !isMatchConfirmed) {
      return _buildBaseCardContainer(
        isUnread: isUnread,
        isLoading: isCardLoading,
        onTap: () => _onNotificationCardTapped(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AWAITING GUEST DEPOSIT',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Text(
                        '✅ Request Accepted!',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUnread) _buildUnreadDot(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for $actorName to pay safety commitment deposit to unlock chat & ticket.',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      if (partyPlanId.isNotEmpty) {
                        setState(() => _navigatingCardIds.add(cardId));
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartyPlanDetailScreen(
                              plan: {'id': partyPlanId, ...data},
                            ),
                          ),
                        ).then((_) {
                          if (mounted) {
                            setState(() => _navigatingCardIds.remove(cardId));
                            _fetchNotifications();
                          }
                        });
                      }
                    },
                    icon: const Icon(
                      Icons.visibility_rounded,
                      size: 14,
                      color: Color(0xFF7C3AED),
                    ),
                    label: const Text(
                      'View Plan Details',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7C3AED)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isMatchConfirmed
                      ? const Color(0xFFE0E7FF)
                      : const Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMatchConfirmed
                      ? Icons.forum_rounded
                      : Icons.check_circle_rounded,
                  color: isMatchConfirmed
                      ? LunaraTheme.electricViolet
                      : const Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMatchConfirmed ? 'MATCH CONFIRMED' : 'ACTION REQUIRED',
                      style: TextStyle(
                        color: isMatchConfirmed
                            ? LunaraTheme.electricViolet
                            : const Color(0xFF10B981),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      isMatchConfirmed
                          ? '🎉 Party Plan Confirmed!'
                          : '✅ Invite Accepted!',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isMatchConfirmed
                ? 'Your safety deposit is paid! Chat is unlocked.'
                : body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (isMatchConfirmed)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            user: {
                              'id': actorId,
                              'firstName': actorName,
                              'contextType': 'party_plan',
                              'planId': partyPlanId,
                            },
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanTicketScreen(
                            request: item,
                            plan: {'id': partyPlanId, ...data},
                            isHost: isHostOfPlan,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(
                      Icons.confirmation_number_rounded,
                      size: 14,
                      color: Color(0xFF7C3AED),
                    ),
                    label: const Text(
                      'View Ticket',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7C3AED)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                  child: LunaraCountdownButton(
                    paymentDeadlineAt:
                        data['paymentDeadlineAt'] ??
                        data['payment_deadline_at'],
                    acceptedAt: data['acceptedAt'] ?? data['accepted_at'],
                    amount: depositAmount,
                    onTap: () async {
                      _markAsRead(item);
                      if (requestId.isNotEmpty) {
                        final bool? sheetSuccess = await SmartCheckoutSheet.show(
                          context: context,
                          title: 'Party Plan Safety Deposit',
                          subtitle:
                              'Safety commitment deposit for Party Plan at $venueName',
                          itemPrice: depositAmount,
                          onWalletPayment: () async {
                            final res = await ApiService.payWithWallet(
                              amount: depositAmount,
                              planId: data['partyPlanId']?.toString(),
                              paymentType: 'commitment_deposit',
                            );
                            if (res != null && res['success'] == true) {
                              final txId =
                                  res['data']?['transactionId']?.toString() ??
                                  'wallet';
                              final confirmRes = await ApiService.post(
                                '/api/mobile/party-plans/requests/$requestId/joiner-pay',
                                body: {
                                  'userId': ApiService.currentUserId ?? '',
                                  'razorpay_order_id': 'order_mock_wallet',
                                  'razorpay_payment_id': 'wallet_$txId',
                                  'razorpay_signature': 'mock_signature',
                                },
                              );
                              if (confirmRes.statusCode == 200) {
                                return true;
                              }
                            }
                            return false;
                          },
                          onDirectPayment: () async {
                            _startRazorpayDirectPayment(
                              requestId: requestId,
                              venueName: venueName,
                              onSuccess: () => _fetchNotifications(),
                            );
                          },
                          onHybridPayment: (shortfall) async {
                            final confirmRes = await ApiService.post(
                              '/api/mobile/party-plans/requests/$requestId/joiner-pay',
                              body: {
                                'userId': ApiService.currentUserId ?? '',
                                'razorpay_order_id': 'order_mock_hybrid',
                                'razorpay_payment_id':
                                    'pay_hybrid_${DateTime.now().millisecondsSinceEpoch}',
                                'razorpay_signature': 'mock_signature',
                              },
                            );
                            if (confirmRes.statusCode == 200 && mounted) {
                              _fetchNotifications();
                            }
                          },
                        );

                        if (sheetSuccess == true && mounted) {
                          TopNotificationBanner.show(
                            title: 'Safety Deposit Paid! 🎉',
                            body: 'Booking confirmed via Smart Wallet for $venueName.',
                          );
                          ApiService.notifyFeedNeedsRefresh();
                          _fetchNotifications();
                          final planId = data['partyPlanId']?.toString() ?? '';
                          if (planId.isNotEmpty) {
                            setState(() => _navigatingCardIds.add(cardId));
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartyPlanTicketScreen(
                                  request: const {},
                                  plan: {'id': planId, 'venue': {'name': venueName}},
                                  isHost: false,
                                ),
                              ),
                            ).then((_) {
                              if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                            });
                          }
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loadingActionKeys.contains('${item['id']}:DECLINE')
                      ? null
                      : () => _handleNotificationAction(item, 'DECLINE'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: _loadingActionKeys.contains('${item['id']}:DECLINE')
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF94A3B8),
                          ),
                        )
                      : const Icon(
                          Icons.close,
                          color: Color(0xFF94A3B8),
                          size: 18,
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── SM1. Strangers Meet Request Received Card (Host sees incoming join request) ──
  Widget _buildStrangersMeetRequestReceivedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId) || _loadingActionKeys.contains(cardId);
    final actor = item['actor'] ?? item['sender'];
    final actorName = actor is Map
        ? '${actor['firstName'] ?? ''} ${actor['lastName'] ?? ''}'.trim()
        : (item['metadata']?['requesterName']?.toString() ?? 'Someone');
    final data = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'])
        : (item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : <String, dynamic>{});
    final meetId = (data['meetId'] ?? data['strangersMeetId'] ?? data['planId'] ?? item['entityId'] ?? '').toString();
    final joinerId = (data['joinerId'] ?? data['requestId'] ?? (actor is Map ? (actor['id'] ?? actor['userId']) : '') ?? '').toString();
    final venueName = data['venueName']?.toString() ?? 'Venue';
    final body =
        item['body']?.toString() ??
        '$actorName requested to join your Stranger Meet at $venueName.';
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);

    final acceptKey = '$cardId:ACCEPT';
    final declineKey = '$cardId:DECLINE';
    final isAccepting = _loadingActionKeys.contains(acceptKey);
    final isDeclining = _loadingActionKeys.contains(declineKey);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LunaraProfileImage(
                userData: actor is Map ? Map<String, dynamic>.from(actor) : {},
                radius: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STRANGER MEET',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      actorName.isNotEmpty
                          ? '$actorName sent a join request'
                          : 'New Stranger Meet Request',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (isAccepting || isDeclining)
                      ? null
                      : () async {
                          _markAsRead(item);
                          setState(() => _loadingActionKeys.add(acceptKey));
                          try {
                            if (meetId.isNotEmpty && joinerId.isNotEmpty) {
                              final ok = await ApiService.handleStrangersMeetJoinRequest(meetId, joinerId, 'accept');
                              if (ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Join request approved! Waiting for participant payment.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                _fetchNotifications();
                              }
                            } else {
                              await _handleNotificationAction(item, 'ACCEPT');
                            }
                          } finally {
                            if (mounted) setState(() => _loadingActionKeys.remove(acceptKey));
                          }
                        },
                  icon: isAccepting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                  label: Text(
                    isAccepting ? 'Approving...' : 'Approve',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (isAccepting || isDeclining)
                      ? null
                      : () async {
                          _markAsRead(item);
                          setState(() => _loadingActionKeys.add(declineKey));
                          try {
                            if (meetId.isNotEmpty && joinerId.isNotEmpty) {
                              final ok = await ApiService.handleStrangersMeetJoinRequest(meetId, joinerId, 'reject');
                              if (ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Join request declined.'),
                                    backgroundColor: Colors.grey,
                                  ),
                                );
                                _fetchNotifications();
                              }
                            } else {
                              await _handleNotificationAction(item, 'DECLINE');
                            }
                          } finally {
                            if (mounted) setState(() => _loadingActionKeys.remove(declineKey));
                          }
                        },
                  icon: isDeclining
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF64748B)),
                        )
                      : const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                  label: Text(
                    isDeclining ? 'Declining...' : 'Decline',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── SM2. Strangers Meet Request Accepted Card ─────────────────────────────
  Widget _buildStrangersMeetAcceptedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final body =
        item['body']?.toString() ?? 'Pay the entry fee to secure your spot!';
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);
    final data = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'])
        : (item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : <String, dynamic>{});
    final meetId = (data['meetId'] ?? data['strangersMeetId'] ?? data['planId'] ?? item['entityId'] ?? '').toString();
    final venueName = data['venueName']?.toString() ?? 'Venue';
    
    double entryFee = 0.0;
    final rawFee = data['chargesPerHead'] ?? data['paymentAmount'] ?? data['amount'] ?? item['amount'];
    if (rawFee is num) {
      entryFee = rawFee.toDouble();
    } else if (rawFee is String) {
      entryFee = double.tryParse(rawFee) ?? 0.0;
    }

    final currentUid = ApiService.currentUserId ?? '';
    final meetHostId = (data['hostId'] ?? data['userId'] ?? item['hostId'] ?? '').toString();
    final bool isHostOfMeet = currentUid.isNotEmpty && meetHostId.isNotEmpty && currentUid == meetHostId;

    final String paymentStatus =
        (data['joinerPaymentStatus'] ??
                data['paymentStatus'] ??
                item['paymentStatus'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();

    final String status =
        (data['status'] ?? item['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    final bool isPaid =
        paymentStatus == 'paid' ||
        paymentStatus == 'completed' ||
        status == 'paid' ||
        status == 'confirmed' ||
        status == 'completed' ||
        data['isPaid'] == true ||
        item['isPaid'] == true;

    final actor = item['actor'] ?? item['sender'] ?? item['actorUser'];
    final actorId =
        (actor is Map ? (actor['id'] ?? actor['userId']) : null)?.toString() ??
        '';
    final actorName =
        (actor is Map
                ? (actor['firstName'] ?? actor['name'] ?? 'Host')
                : 'Host')
            .toString();

    final bool isCardLoading = _navigatingCardIds.contains(cardId) || _loadingActionKeys.contains(cardId);

    if (isHostOfMeet && !isPaid) {
      return _buildBaseCardContainer(
        isUnread: isUnread,
        isLoading: isCardLoading,
        onTap: () => _onNotificationCardTapped(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AWAITING PARTICIPANT PAYMENT',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Text(
                        '✅ Join Request Approved!',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUnread) _buildUnreadDot(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You approved $actorName for your Stranger Meet at $venueName. Waiting for payment to confirm seat.',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveFeedScreen(initialTabIndex: 0),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(
                      Icons.visibility_rounded,
                      size: 14,
                      color: Color(0xFF7C3AED),
                    ),
                    label: const Text(
                      'View Meet in Feed',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7C3AED)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPaid
                      ? const Color(0xFFE0E7FF)
                      : const Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPaid
                      ? Icons.forum_rounded
                      : Icons.check_circle_rounded,
                  color: isPaid
                      ? LunaraTheme.electricViolet
                      : const Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPaid ? 'SEAT CONFIRMED' : 'ACTION REQUIRED',
                      style: TextStyle(
                        color: isPaid
                            ? LunaraTheme.electricViolet
                            : const Color(0xFF10B981),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      isPaid
                          ? '🎉 Stranger Meet Confirmed!'
                          : '✅ Request Approved!',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPaid
                ? 'Your seat at $venueName is confirmed! Chat is unlocked.'
                : body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (isPaid)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            user: {
                              'id': actorId.isNotEmpty ? actorId : meetHostId,
                              'firstName': actorName,
                              'contextType': 'strangers_meet',
                              'planId': meetId,
                            },
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      try {
                        final smReq = StrangersMeetRequest.fromJson({'id': meetId, ...data});
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StrangersMeetTicketScreen(request: smReq),
                          ),
                        );
                      } catch (e) {
                        debugPrint('Error opening SM ticket: $e');
                      } finally {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      }
                    },
                    icon: const Icon(
                      Icons.confirmation_number_rounded,
                      size: 14,
                      color: Color(0xFF7C3AED),
                    ),
                    label: const Text(
                      'View Ticket',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7C3AED)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      try {
                        final smReq = StrangersMeetRequest.fromJson({'id': meetId, ...data});
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StrangersMeetPaymentScreen(
                              request: smReq,
                              onPaymentSuccess: () => _fetchNotifications(),
                              isJoinPayment: true,
                            ),
                          ),
                        ).then((_) {
                          if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                        });
                      } catch (e) {
                        debugPrint('Error opening SM payment: $e');
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      }
                    },
                    icon: const Icon(Icons.payment_rounded, size: 14, color: Colors.white),
                    label: Text(
                      entryFee > 0 ? 'Pay Entry Fee (₹${entryFee.toStringAsFixed(0)})' : 'Pay Entry Fee',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loadingActionKeys.contains('${item['id']}:DECLINE')
                      ? null
                      : () => _handleNotificationAction(item, 'DECLINE'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: _loadingActionKeys.contains('${item['id']}:DECLINE')
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF94A3B8),
                          ),
                        )
                      : const Icon(
                          Icons.close,
                          color: Color(0xFF94A3B8),
                          size: 18,
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── SM3. Strangers Meet Posted Card ───────────────────────────────────────
  Widget _buildStrangersMeetPostedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId) || _loadingActionKeys.contains(cardId);
    final title = (item['title'] ?? '🤝 Stranger Meet').toString();
    final body = item['body']?.toString() ?? 'Your Stranger Meet is live!';
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);

    final data = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'])
        : (item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : <String, dynamic>{});
    final meetId = (data['meetId'] ?? data['strangersMeetId'] ?? data['planId'] ?? item['entityId'] ?? '').toString();
    final venueName = data['venueName']?.toString() ?? 'Venue';
    final hostPaymentStatus = (data['hostPaymentStatus'] ?? data['paymentStatus'] ?? '').toString().toLowerCase();
    final bool isHostPaid = hostPaymentStatus == 'paid' || hostPaymentStatus == 'completed';

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STRANGER MEET',
                      style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      title.isNotEmpty ? title : '🤝 Stranger Meet at $venueName',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10.5,
                    ),
                  ),
                  if (isUnread) ...[
                    const SizedBox(height: 4),
                    _buildUnreadDot(),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isHostPaid && (data['paymentAmount'] != null || data['depositAmount'] != null)) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      try {
                        final smReq = StrangersMeetRequest.fromJson({'id': meetId, ...data});
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StrangersMeetPaymentScreen(
                              request: smReq,
                              onPaymentSuccess: () => _fetchNotifications(),
                              isJoinPayment: false,
                            ),
                          ),
                        ).then((_) {
                          if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                        });
                      } catch (e) {
                        debugPrint('Error opening SM host pay: $e');
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      }
                    },
                    icon: const Icon(Icons.payment_rounded, size: 14, color: Colors.white),
                    label: const Text(
                      'Pay Deposit',
                      style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _markAsRead(item);
                    setState(() => _navigatingCardIds.add(cardId));
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveFeedScreen(initialTabIndex: 0),
                      ),
                    ).then((_) {
                      if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                    });
                  },
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: Color(0xFF7C3AED),
                  ),
                  label: const Text(
                    'View Meet',
                    style: TextStyle(
                      color: Color(0xFF7C3AED),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── LP1. Large Party / Group Party Card ──────────────────────────────────
  Widget _buildLargePartyCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId) || _loadingActionKeys.contains(cardId);
    final title = (item['title'] ?? '👥 Large Party Booking').toString();
    final body = item['body']?.toString() ?? 'Large party booking details.';
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);

    final data = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'])
        : (item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : <String, dynamic>{});
    final bookingData = Map<String, dynamic>.from(data['booking'] is Map ? data['booking'] : data);
    final venueMap = bookingData['venue'] is Map
        ? Map<String, dynamic>.from(bookingData['venue'])
        : {'name': bookingData['venueName'] ?? data['venueName'] ?? 'Venue'};
    final bookingId = (data['partyId'] ?? data['bookingId'] ?? data['groupPartyId'] ?? item['entityId'] ?? item['id'] ?? '').toString();

    final status = (bookingData['status'] ?? data['status'] ?? item['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (bookingData['paymentStatus'] ?? data['paymentStatus'] ?? item['paymentStatus'] ?? '').toString().toLowerCase();
    final bool isPaid = paymentStatus == 'paid' || paymentStatus == 'completed' || status == 'paid' || status == 'confirmed' || status == 'completed' || item['isPaid'] == true || data['isPaid'] == true;

    double depositAmount = 1999.0;
    final rawAmount = bookingData['totalAmount'] ?? bookingData['depositAmount'] ?? data['paymentAmount'] ?? data['depositAmount'] ?? item['amount'];
    if (rawAmount is num) {
      depositAmount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      depositAmount = double.tryParse(rawAmount) ?? 1999.0;
    }

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFC084FC)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPaid ? 'BOOKING CONFIRMED' : 'ACTION REQUIRED',
                      style: TextStyle(
                        color: isPaid ? const Color(0xFF10B981) : const Color(0xFFD97706),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      title.isNotEmpty ? title : '👥 Large Party Booking',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isPaid) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LargePartyTicketScreen(
                            booking: bookingData,
                            venue: venueMap,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(
                      Icons.confirmation_number_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'View Ticket',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      try {
                        final vName = venueMap['name']?.toString() ?? 'Venue';
                        final cleanId = ApiService.cleanBookingId(bookingId);
                        await SmartCheckoutSheet.show(
                          context: context,
                          title: 'Large Party Booking',
                          subtitle: 'Deposit payment for Large Party at $vName',
                          itemPrice: depositAmount,
                          onWalletPayment: () async {
                            final res = await ApiService.payWithWallet(
                              amount: depositAmount,
                              bookingId: cleanId,
                              paymentType: 'group_party',
                            );
                            if (res != null && res['success'] == true) {
                              final transactionId = res['data']?['transactionId']?.toString() ?? 'wallet';
                              final confirmRes = await ApiService.verifyLargePartyPayment(
                                cleanId,
                                razorpayOrderId: 'order_mock_wallet',
                                razorpayPaymentId: 'wallet_$transactionId',
                                razorpaySignature: 'mock_signature',
                              );
                              if (confirmRes) {
                                _fetchNotifications();
                                return true;
                              }
                            }
                            return false;
                          },
                          onDirectPayment: () async {
                            final result = await ApiService.initiateLargePartyPayment(cleanId);
                            if (result != null && result['success'] == true) {
                              _fetchNotifications();
                            }
                          },
                          onHybridPayment: (shortfall) async {
                            final result = await ApiService.initiateLargePartyPayment(cleanId);
                            if (result != null && result['success'] == true) {
                              _fetchNotifications();
                            }
                          },
                        );
                      } catch (e) {
                        debugPrint('Error starting large party payment: $e');
                      } finally {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      }
                    },
                    icon: const Icon(Icons.payment_rounded, size: 14, color: Colors.white),
                    label: Text(
                      'Pay Deposit (₹${depositAmount.toStringAsFixed(0)})',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _markAsRead(item);
                    setState(() => _navigatingCardIds.add(cardId));
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveFeedScreen(initialTabIndex: 0),
                      ),
                    ).then((_) {
                      if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                    });
                  },
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: Color(0xFF7C3AED),
                  ),
                  label: const Text(
                    'View in Feed',
                    style: TextStyle(
                      color: Color(0xFF7C3AED),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPartyPlanCancellationCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final data = item['metadata'] is Map
        ? item['metadata'] as Map<String, dynamic>
        : (item['data'] is Map
              ? item['data'] as Map<String, dynamic>
              : <String, dynamic>{});

    final String planId = (data['planId'] ?? item['entityId'] ?? '').toString();
    final String requestId = (data['requestId'] ?? '').toString();
    final String title = (item['title'] ?? 'Party Plan Cancellation')
        .toString();
    final String body = (item['body'] ?? '').toString();
    final String timeStr = _formatTimeAgo(item['createdAt']);

    final String reqStatus =
        (data['status'] ?? item['cancellationStatus'] ?? 'pending')
            .toString()
            .toLowerCase();
    final String requestedById =
        (data['requestedById'] ?? item['requestedById'] ?? '').toString();
    final String recipientUserId =
        (data['recipientUserId'] ?? item['recipientUserId'] ?? '').toString();
    final bool isRecipient =
        ApiService.currentUserId != null &&
        ((requestedById.isNotEmpty && requestedById != ApiService.currentUserId) ||
         (recipientUserId.isNotEmpty && recipientUserId == ApiService.currentUserId));
    final bool isCancelled =
        reqStatus == 'approved' ||
        reqStatus == 'completed' ||
        reqStatus == 'cancelled' ||
        body.toLowerCase().contains('cancelled') ||
        title.toLowerCase().contains('cancelled');

    final cardId = (item['id'] ?? item['entityId'] ?? planId).toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCancelled
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCancelled ? 'CANCELLED' : 'CANCELLATION REQUESTED',
                  style: TextStyle(
                    color: isCancelled ? Colors.redAccent : Colors.orangeAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10.5,
                ),
              ),
              if (isUnread) ...[const SizedBox(width: 6), _buildUnreadDot()],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (isCancelled)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  _markAsRead(item);
                  if (cardId.isNotEmpty) setState(() => _navigatingCardIds.add(cardId));
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LunaraWalletScreen(),
                    ),
                  ).then((_) {
                    if (mounted && cardId.isNotEmpty) setState(() => _navigatingCardIds.remove(cardId));
                  });
                },
                icon: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                label: const Text(
                  'View Wallet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else if (isRecipient && (requestId.isNotEmpty || planId.isNotEmpty))
            Builder(
              builder: (context) {
                final keepKey = 'CANCEL_KEEP:$planId:$requestId';
                final approveKey = 'CANCEL_APPROVE:$planId:$requestId';
                final isKeeping = _loadingActionKeys.contains(keepKey);
                final isApproving = _loadingActionKeys.contains(approveKey);
                final isBusy = isKeeping || isApproving;

                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isBusy
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                setState(() => _loadingActionKeys.add(keepKey));
                                final prevMetadata = item['metadata'] is Map ? Map<String, dynamic>.from(item['metadata']) : null;
                                setState(() {
                                  item['read'] = true;
                                  item['isRead'] = true;
                                  item['metadata'] = {
                                    ...(prevMetadata ?? {}),
                                    'status': 'ACTIONED',
                                    'actionExecuted': 'reject',
                                  };
                                });
                                _markAsRead(item);
                                try {
                                  final res = await ApiService.respondToPartyPlanCancellationRequest(
                                    planId: planId,
                                    requestId: requestId,
                                    action: 'reject',
                                  );
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          res['message'] ?? 'Cancellation request declined. Party Plan remains active.',
                                        ),
                                        backgroundColor: Colors.grey.shade800,
                                      ),
                                    );
                                  }
                                  _fetchNotifications();
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      if (prevMetadata != null) {
                                        item['metadata'] = prevMetadata;
                                      } else {
                                        item['metadata']?.remove('status');
                                      }
                                    });
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _loadingActionKeys.remove(keepKey));
                                  }
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isKeeping
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'KEEPING...',
                                    style: TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'KEEP PLAN',
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isBusy
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                setState(() => _loadingActionKeys.add(approveKey));
                                final prevMetadata = item['metadata'] is Map ? Map<String, dynamic>.from(item['metadata']) : null;
                                setState(() {
                                  item['read'] = true;
                                  item['isRead'] = true;
                                  item['metadata'] = {
                                    ...(prevMetadata ?? {}),
                                    'status': 'ACTIONED',
                                    'actionExecuted': 'approve',
                                  };
                                });
                                _markAsRead(item);
                                try {
                                  final res = await ApiService.respondToPartyPlanCancellationRequest(
                                    planId: planId,
                                    requestId: requestId,
                                    action: 'approve',
                                  );
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          res['message'] ?? 'Party Plan cancelled. Commitment deposits credited to wallets!',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                  _fetchNotifications();
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      if (prevMetadata != null) {
                                        item['metadata'] = prevMetadata;
                                      } else {
                                        item['metadata']?.remove('status');
                                      }
                                    });
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _loadingActionKeys.remove(approveKey));
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isApproving
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'CANCELLING...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'ACCEPT CANCELLATION',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            )
          else
            const Text(
              'Waiting for participant confirmation.',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSafetyCheckCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final data = item['metadata'] is Map
        ? item['metadata'] as Map<String, dynamic>
        : (item['data'] is Map
              ? item['data'] as Map<String, dynamic>
              : <String, dynamic>{});

    final checkId = (data['checkId'] ??
            data['id'] ??
            item['entityId'] ??
            item['id'] ??
            '')
        .toString();

    final title = (item['title'] ?? 'Safety Check: Has your party ended?').toString();
    final body = (item['body'] ?? 'Your party started recently. Please confirm you are safe & sound.').toString();
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['created_at']);
    final safetyStatus = (data['safetyStatus'] ?? item['safetyStatus'] ?? 'NO_RESPONSE').toString();
    final rawDate = data['partyDate'] ?? item['createdAt'] ?? item['created_at'];
    bool isOlderThan12Hours = false;
    if (rawDate != null) {
      try {
        final dt = DateTime.parse(rawDate.toString()).toLocal();
        if (DateTime.now().difference(dt).inHours >= 12) {
          isOlderThan12Hours = true;
        }
      } catch (_) {}
    }
    final isAnswered = safetyStatus == 'SAFE' || safetyStatus == 'NEED_HELP' || safetyStatus == 'EXTENDED' || item['answered'] == true || isOlderThan12Hours;

    final isSafeKey = 'SAFETY_SAFE:$checkId';
    final isHelpKey = 'SAFETY_HELP:$checkId';
    final isActionLoading = _loadingActionKeys.contains(isSafeKey) || _loadingActionKeys.contains(isHelpKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread ? const Color(0xFF10B981).withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
          width: isUnread ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _markAsRead(item);
            PartySafetyCheckDialog.showIfNeeded(
              context,
              onSubmitted: () {
                setState(() {
                  item['isRead'] = true;
                  item['answered'] = true;
                  item['safetyStatus'] = 'SAFE';
                });
                _fetchNotifications();
              },
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Shield Icon + Title + Time
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: safetyStatus == 'NEED_HELP'
                            ? Colors.red.withValues(alpha: 0.12)
                            : const Color(0xFF10B981).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        safetyStatus == 'NEED_HELP'
                            ? Icons.warning_rounded
                            : Icons.shield_outlined,
                        size: 20,
                        color: safetyStatus == 'NEED_HELP'
                            ? Colors.red.shade700
                            : const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (timeStr.isNotEmpty)
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            body,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF475569),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Action area
                if (isAnswered)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: safetyStatus == 'NEED_HELP'
                          ? Colors.red.withValues(alpha: 0.08)
                          : const Color(0xFF10B981).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          safetyStatus == 'NEED_HELP' ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                          size: 16,
                          color: safetyStatus == 'NEED_HELP' ? Colors.red.shade700 : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          safetyStatus == 'NEED_HELP'
                              ? 'Alert Reported to Safety Team'
                              : 'Confirmed Safe & Reached Home',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: safetyStatus == 'NEED_HELP' ? Colors.red.shade800 : const Color(0xFF065F46),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      // 🟢 Yes, I'm Safe button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isActionLoading
                              ? null
                              : () async {
                                  _markAsRead(item);
                                  setState(() => _loadingActionKeys.add(isSafeKey));
                                  try {
                                    final res = await ApiService.submitSafetyCheckStatus(
                                      checkId: checkId,
                                      safetyStatus: 'SAFE',
                                      notes: 'Confirmed safe via Notification Center',
                                    );
                                    if (mounted && res['success'] == true) {
                                      setState(() {
                                        item['safetyStatus'] = 'SAFE';
                                        item['answered'] = true;
                                        item['isRead'] = true;
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('🟢 Confirmed safe! Stay safe!'),
                                          backgroundColor: const Color(0xFF10B981),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint('Error confirming safety: $e');
                                  } finally {
                                    if (mounted) {
                                      setState(() => _loadingActionKeys.remove(isSafeKey));
                                    }
                                  }
                                },
                          icon: _loadingActionKeys.contains(isSafeKey)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                          label: const Text(
                            'I\'M SAFE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 🔴 No, Need Help button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isActionLoading
                              ? null
                              : () {
                                  _markAsRead(item);
                                  PartySafetyCheckDialog.showIfNeeded(
                                    context,
                                    onSubmitted: () {
                                      setState(() {
                                        item['isRead'] = true;
                                        item['answered'] = true;
                                        item['safetyStatus'] = 'NEED_HELP';
                                      });
                                      _fetchNotifications();
                                    },
                                  );
                                },
                          icon: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.redAccent),
                          label: const Text(
                            'NEED HELP',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: Colors.redAccent,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPartyPlanInvitationCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final data = item['metadata'] is Map
        ? item['metadata'] as Map<String, dynamic>
        : (item['data'] is Map
              ? item['data'] as Map<String, dynamic>
              : <String, dynamic>{});

    final String requestId = (data['requestId'] ?? data['planId'] ?? data['partyPlanId'] ?? item['entityId'] ?? '').toString();
    final String currentUid = ApiService.currentUserId ?? '';
    final String senderId = (data['senderId'] ?? data['hostId'] ?? data['userId'] ?? item['senderId'] ?? item['actorUserId'] ?? '').toString();
    final bool isSender = currentUid.isNotEmpty && senderId.isNotEmpty && currentUid == senderId;

    final String title = isSender
        ? 'Party Plan Invitation Sent'
        : (item['title'] ?? '🎉 Party Plan Invitation').toString();
    final String body = (item['body'] ?? (isSender
            ? 'You sent a private invitation for this Party Plan. Waiting for response.'
            : 'You have been invited to join a Party Plan!'))
        .toString();
    final String timeStr = _formatTimeAgo(item['createdAt']);

    final String reqStatus = (data['status'] ?? item['status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final bool isAccepted =
        reqStatus == 'accepted' ||
        reqStatus == 'payment_pending' ||
        reqStatus == 'confirmed' ||
        reqStatus == 'paid';

    final String badgeText = isAccepted
        ? 'INVITE ACCEPTED'
        : (isSender ? 'INVITATION SENT' : 'PRIVATE INVITATION');

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isAccepted
                      ? Colors.green.withValues(alpha: 0.15)
                      : const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: isAccepted ? Colors.green : const Color(0xFF8B5CF6),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10.5,
                ),
              ),
              if (isUnread) ...[const SizedBox(width: 6), _buildUnreadDot()],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (isAccepted || isSender)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  _markAsRead(item);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                label: Text(
                  isAccepted ? 'View Plan Details' : 'View Plan',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            Builder(
              builder: (context) {
                final acceptKey = 'ACCEPT_INVITE:$requestId';
                final isAccepting = _loadingActionKeys.contains(acceptKey);
                return Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isAccepting
                            ? null
                            : () async {
                                _markAsRead(item);
                                if (requestId.isNotEmpty) {
                                  setState(() => _loadingActionKeys.add(acceptKey));
                                  try {
                                    final res = await ApiService.acceptPartyPlanInvite(
                                      requestId,
                                    );
                                    if (mounted && context.mounted) {
                                      if (res != null && res['success'] == true) {
                                        final bool isSelfPay = res['isSelfPay'] == true || (res['message']?.toString().toLowerCase().contains('host') ?? false);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              res['message'] ?? (isSelfPay
                                                  ? '🎉 Invite Accepted! (Paid by Host)'
                                                  : '🎉 Invite Accepted! Please pay the safety deposit to confirm.'),
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        _fetchNotifications();
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              res?['message'] ?? 'Failed to accept invite',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    debugPrint('Error accepting invite: $e');
                                    if (mounted && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _loadingActionKeys.remove(acceptKey));
                                    }
                                  }
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isAccepting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'ACCEPTING...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'ACCEPT INVITE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isAccepting
                            ? null
                            : () {
                                _markAsRead(item);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                                  ),
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'VIEW DETAILS',
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDeclinedRequestCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final String title = item['title']?.toString() ?? 'Declined Request ❌';
    String body = item['body']?.toString() ?? 'Your request was declined.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    // Resolve metadata — check both 'metadata' and 'data' keys
    final data = item['metadata'] is Map
        ? item['metadata'] as Map<String, dynamic>
        : (item['data'] is Map
              ? item['data'] as Map<String, dynamic>
              : <String, dynamic>{});

    // Merge actor data: DB-joined actor takes priority but metadata actor fills gaps
    final dbActor = item['actor'] ?? item['sender'];
    final metaActor = data['actor'];
    final dbActorMap = dbActor is Map
        ? Map<String, dynamic>.from(dbActor)
        : <String, dynamic>{};
    final metaActorMap = metaActor is Map
        ? Map<String, dynamic>.from(metaActor)
        : <String, dynamic>{};
    // Merged: metadata actor fills in fields not present in DB actor
    final actorMap = {...metaActorMap, ...dbActorMap};

    // Resolve name: prefer DB actor firstName, fall back to metadata
    final String declinerName = (() {
      final firstName = (actorMap['firstName'] ?? '').toString().trim();
      final lastName = (actorMap['lastName'] ?? '').toString().trim();
      if (firstName.isNotEmpty) {
        return '$firstName $lastName'.trim();
      }
      return (data['actorName'] ?? 'the host').toString().trim();
    })();

    // Resolve photo URL — guard against empty strings
    String pickNonEmpty(List<String?> candidates) {
      for (final c in candidates) {
        if (c != null && c.trim().isNotEmpty) return c.trim();
      }
      return '';
    }

    final String declinerPhoto = pickNonEmpty([
      actorMap['profilePhotoUrl']?.toString(),
      actorMap['profileImageUrl']?.toString(),
      actorMap['photoUrl']?.toString(),
      metaActorMap['profilePhotoUrl']?.toString(),
      metaActorMap['profileImageUrl']?.toString(),
      data['actorProfilePhotoUrl']?.toString(),
    ]);

    // Replace generic "by the host" with actual decliner name if body hasn't been personalised yet
    if (declinerName.isNotEmpty && declinerName != 'the host') {
      if (body.contains('by the host.')) {
        body = body.replaceAll('by the host.', 'by $declinerName.');
      } else if (body.contains('by the host')) {
        body = body.replaceAll('by the host', 'by $declinerName');
      }
    }

    final userData = {
      ...actorMap,
      'firstName': declinerName,
      'profilePhotoUrl': declinerPhoto,
      'profileImageUrl': declinerPhoto,
    };

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(userData),
            child: declinerPhoto.isNotEmpty
                ? LunaraProfileImage(userData: userData, radius: 22)
                : Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.cancel_rounded,
                      color: Colors.redAccent,
                      size: 22,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'DECLINED',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                    if (isUnread) ...[
                      const SizedBox(width: 6),
                      _buildUnreadDot(),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. Partner Request Card Component ──────────────────────────────────────
  Widget _buildPartnerRequestCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final data = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item['metadata'] is Map
              ? Map<String, dynamic>.from(item['metadata'])
              : <String, dynamic>{});

    final actor = item['actor'] ??
        item['sender'] ??
        data['actor'] ??
        (data['otherUserId'] != null
            ? {
                'id': data['otherUserId'],
                'firstName': data['otherUserName'] ?? 'Partner',
                'profilePhotoUrl': data['otherUserPhoto'],
              }
            : null);

    final actorMap = actor is Map ? Map<String, dynamic>.from(actor) : <String, dynamic>{};
    final actorName = (actorMap['firstName'] ?? data['hostName'] ?? data['otherUserName'] ?? 'A member').toString();
    final venueName = (data['venueName'] ?? 'Upcoming Night').toString();
    final eventDate = (data['eventDate'] ?? '').toString();
    final body = item['body']?.toString() ?? '$actorName invited you to join for Upcoming Night at $venueName!';
    final timeStr = _formatTimeAgo(item['createdAt']);

    final actionStatus = (item['metadata']?['status'] ?? data['status'] ?? '').toString().toUpperCase();
    final actionExecuted = (item['metadata']?['actionExecuted'] ?? data['actionExecuted'] ?? '').toString().toUpperCase();
    final bool isActioned = actionStatus == 'ACTIONED' || actionStatus == 'ACCEPTED' || actionStatus == 'DECLINED' || actionExecuted.isNotEmpty;
    final bool isAccepted = actionExecuted == 'ACCEPT' || actionStatus == 'ACCEPTED' || data['statusText'] == 'Accepted' || data['statusText'] == 'Confirmed & Chat Unlocked';

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openUserProfile(actorMap),
                child: Stack(
                  children: [
                    LunaraProfileImage(
                      userData: actorMap,
                      radius: 22,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.celebration_rounded,
                          color: LunaraTheme.electricViolet,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PARTNER INVITE',
                            style: TextStyle(
                              color: LunaraTheme.electricViolet,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 6),
                          _buildUnreadDot(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'New Partner Request! 🎉',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (venueName.isNotEmpty || eventDate.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded, size: 13, color: LunaraTheme.electricViolet),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      venueName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (eventDate.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
                    const SizedBox(width: 8),
                    const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      eventDate,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isActioned)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: isAccepted ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isAccepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 15,
                    color: isAccepted ? const Color(0xFF15803D) : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isAccepted ? 'INVITE ACCEPTED ✓' : 'INVITE DECLINED',
                    style: TextStyle(
                      color: isAccepted ? const Color(0xFF15803D) : const Color(0xFF64748B),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                if (actorMap.isNotEmpty) ...[
                  OutlinedButton(
                    onPressed: () => _openUserProfile(actorMap),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 38),
                    ),
                    child: const Text(
                      'Profile',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _openUpcomingNightInvite(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(0, 38),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          'ACCEPT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loadingActionKeys.contains('${item['id']}:DECLINE')
                      ? null
                      : () => _handleNotificationAction(item, 'DECLINE'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    backgroundColor: const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 38),
                  ),
                  child: _loadingActionKeys.contains('${item['id']}:DECLINE')
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF64748B),
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, size: 14, color: Color(0xFF64748B)),
                            SizedBox(width: 4),
                            Text(
                              'DECLINE',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 1B. Upcoming Night Cancellation Request Card ──────────────────────────
  Widget _buildUpcomingNightCancellationRequestCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final data = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item['metadata'] is Map
              ? Map<String, dynamic>.from(item['metadata'])
              : <String, dynamic>{});

    final actor = item['actor'] ??
        item['sender'] ??
        data['actor'] ??
        (data['otherUserId'] != null
            ? {
                'id': data['otherUserId'],
                'firstName': data['otherUserName'] ?? 'Partner',
                'profilePhotoUrl': data['otherUserPhoto'],
              }
            : null);

    final actorMap = actor is Map ? Map<String, dynamic>.from(actor) : <String, dynamic>{};
    final actorName = (actorMap['firstName'] ?? data['requesterName'] ?? data['otherUserName'] ?? 'Partner').toString();
    final venueName = (data['venueName'] ?? 'Upcoming Night').toString();
    final eventDate = (data['eventDate'] ?? '').toString();
    final reason = (data['reason'] ?? 'Change of plans').toString();
    final body = item['body']?.toString() ?? '$actorName requested to cancel Upcoming Night at $venueName. Reason: "$reason".';
    final timeStr = _formatTimeAgo(item['createdAt']);

    final actionStatus = (item['metadata']?['status'] ?? data['status'] ?? '').toString().toUpperCase();
    final actionExecuted = (item['metadata']?['actionExecuted'] ?? data['actionExecuted'] ?? '').toString().toUpperCase();
    final bool isActioned = actionStatus == 'ACTIONED' || actionExecuted.isNotEmpty;
    final bool isApproved = actionExecuted == 'ACCEPT_CANCELLATION' || actionStatus == 'APPROVED';

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openUserProfile(actorMap),
                child: Stack(
                  children: [
                    LunaraProfileImage(
                      userData: actorMap,
                      radius: 22,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFE11D48),
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFFE4E6)),
                          ),
                          child: const Text(
                            'CANCELLATION REQUEST',
                            style: TextStyle(
                              color: Color(0xFFE11D48),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 6),
                          _buildUnreadDot(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cancel Upcoming Night? ⚠️',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (venueName.isNotEmpty || eventDate.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded, size: 13, color: LunaraTheme.electricViolet),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      venueName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (eventDate.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
                    const SizedBox(width: 8),
                    const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      eventDate,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isActioned)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: isApproved ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isApproved ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    size: 15,
                    color: isApproved ? const Color(0xFF15803D) : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isApproved ? 'CANCELLATION CONFIRMED & REFUNDED ✓' : 'KEPT ACTIVE',
                    style: TextStyle(
                      color: isApproved ? const Color(0xFF15803D) : const Color(0xFF64748B),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loadingActionKeys.contains('${item['id']}:ACCEPT_CANCELLATION') || _loadingActionKeys.contains('${item['id']}:REJECT_CANCELLATION')
                        ? null
                        : () => _handleNotificationAction(item, 'ACCEPT_CANCELLATION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE11D48),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(0, 38),
                    ),
                    child: _loadingActionKeys.contains('${item['id']}:ACCEPT_CANCELLATION')
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'CONFIRMING...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 15, color: Colors.white),
                              SizedBox(width: 5),
                              Text(
                                'CONFIRM & REFUND',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loadingActionKeys.contains('${item['id']}:ACCEPT_CANCELLATION') || _loadingActionKeys.contains('${item['id']}:REJECT_CANCELLATION')
                      ? null
                      : () => _handleNotificationAction(item, 'REJECT_CANCELLATION'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    backgroundColor: const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 38),
                  ),
                  child: _loadingActionKeys.contains('${item['id']}:REJECT_CANCELLATION')
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'KEEPING...',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, size: 14, color: Color(0xFF64748B)),
                            SizedBox(width: 4),
                            Text(
                              'KEEP ACTIVE',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 2. Interested User Card Component ──────────────────────────────────────
  Widget _buildInterestCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final actor = item['actor'] ?? item['sender'];
    final actorName = actor?['firstName'] ?? actor?['name'] ?? 'Someone';
    final body =
        item['body']?.toString() ??
        '$actorName is interested in your Stranger Meet.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(actor),
            child: Row(
              children: [
                if (actor != null && actor is Map && actor.isNotEmpty) ...[
                  LunaraProfileImage(
                    userData: Map<String, dynamic>.from(actor),
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                ] else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFCE7F3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: LunaraTheme.hotPink,
                      size: 18,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '❤️ New Interest',
                        style: TextStyle(
                          color: LunaraTheme.hotPink,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUnread) _buildUnreadDot(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _onNotificationCardTapped(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'View Interest',
                        style: TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _handleNotificationAction(item, 'DECLINE'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Ignore',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. Request Accepted Card Component ─────────────────────────────────────
  Widget _buildRequestAcceptedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);
    final actor = item['actor'] ?? item['sender'];
    final actorName = actor?['firstName'] ?? actor?['name'] ?? 'User';
    final body = item['body']?.toString() ?? 'You are going together!';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _openUserProfile(actor),
                child: LunaraProfileImage(
                  userData: actor is Map
                      ? Map<String, dynamic>.from(actor)
                      : {},
                  radius: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$actorName accepted your request',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _markAsRead(item);
                    setState(() => _navigatingCardIds.add(cardId));
                    final data = item['data'] is Map
                        ? Map<String, dynamic>.from(item['data'])
                        : (item['metadata'] is Map
                            ? Map<String, dynamic>.from(item['metadata'])
                            : <String, dynamic>{});
                    final bookingData = Map<String, dynamic>.from(data['booking'] is Map ? data['booking'] : data);
                    final venueMap = bookingData['venue'] is Map
                        ? Map<String, dynamic>.from(bookingData['venue'])
                        : {'name': bookingData['venueName'] ?? 'Venue'};
                    final isEventBooking = bookingData['isUpcomingNight'] == true ||
                        bookingData['partyEventId'] != null ||
                        bookingData['partyEvent'] != null ||
                        item['eventDetails']?['isUpcomingNight'] == true ||
                        item['data']?['isUpcomingNight'] == true;
                    final isGroupOrLarge = !isEventBooking && (
                        bookingData['isGroupParty'] == true ||
                        bookingData['isLargePartyRequest'] == true ||
                        bookingData['goingMode'] == 'party_request' ||
                        bookingData['type'] == 'group_party_timeline' ||
                        bookingData['type'] == 'large_party_timeline' ||
                        (item['id']?.toString().startsWith('group_party_') ?? false) ||
                        (item['id']?.toString().startsWith('large_party_') ?? false));

                    if (isGroupOrLarge) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LargePartyTicketScreen(
                            booking: bookingData,
                            venue: venueMap,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    } else {
                      final eventTitle = bookingData['partyEvent']?['title'] ??
                          bookingData['partySubject'] ??
                          bookingData['eventTitle'] ??
                          item['eventDetails']?['title'] ??
                          item['eventDetails']?['subject'];
                      final bannerUrl = bookingData['partyEvent']?['imagePath'] ??
                          bookingData['partyEvent']?['bannerImageUrl'] ??
                          bookingData['bannerImageUrl'] ??
                          item['eventDetails']?['bannerImageUrl'];

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DigitalTicketScreen(
                            venue: venueMap,
                            date: bookingData['bookingDate']?.toString() ?? bookingData['date']?.toString(),
                            time: bookingData['startTime']?.toString() ?? bookingData['time']?.toString(),
                            table: isEventBooking ? (eventTitle?.toString() ?? 'Event Entry') : 'Confirmed Entry',
                            guests: (bookingData['numberOfGuests'] ?? bookingData['guestCount'] ?? 1).toString(),
                            package: isEventBooking ? (eventTitle?.toString() ?? 'Party Ticket') : 'Confirmed Entry',
                            totalPrice: bookingData['totalAmount'] != null ? '₹${bookingData['totalAmount']}' : 'PAID',
                            ticketId: (bookingData['ticketCode'] ?? bookingData['id'] ?? item['id'])?.toString(),
                            status: 'CONFIRMED',
                            booking: bookingData,
                            user: ApiService.cachedCurrentUser,
                            eventTitle: eventTitle?.toString(),
                            bannerImageUrl: bannerUrl?.toString(),
                            isUpcomingNight: isEventBooking,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    }
                  },
                  icon: const Icon(
                    Icons.confirmation_number_outlined,
                    size: 14,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'View Ticket',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _markAsRead(item);
                    setState(() => _navigatingCardIds.add(cardId));
                    final actor = item['actor'] ?? item['sender'];
                    final data = item['data'] is Map
                        ? Map<String, dynamic>.from(item['data'])
                        : (item['metadata'] is Map
                            ? Map<String, dynamic>.from(item['metadata'])
                            : <String, dynamic>{});
                    final partner = actor is Map
                        ? Map<String, dynamic>.from(actor)
                        : (data['user'] is Map ? Map<String, dynamic>.from(data['user']) : <String, dynamic>{});
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(user: partner),
                      ),
                    ).then((_) {
                      if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Open Chat',
                        style: TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 4. Booking Confirmed Card Component ───────────────────────────────────
  Widget _buildBookingConfirmedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);
    final body =
        item['body']?.toString() ??
        'Your booking is confirmed. Get ready for the party!';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Booking Confirmed 🎉',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _markAsRead(item);
                    setState(() => _navigatingCardIds.add(cardId));
                    final data = item['data'] is Map
                        ? Map<String, dynamic>.from(item['data'])
                        : (item['metadata'] is Map
                            ? Map<String, dynamic>.from(item['metadata'])
                            : <String, dynamic>{});
                    final bookingData = Map<String, dynamic>.from(data['booking'] is Map ? data['booking'] : data);
                    final venueMap = bookingData['venue'] is Map
                        ? Map<String, dynamic>.from(bookingData['venue'])
                        : {'name': bookingData['venueName'] ?? 'Venue'};
                    final isGroupOrLarge = (bookingData['numberOfGuests'] ?? bookingData['guestCount'] ?? 1) > 1 ||
                        bookingData['isGroupParty'] == true ||
                        bookingData['isLargePartyRequest'] == true ||
                        bookingData['goingMode'] == 'party_request' ||
                        bookingData['type'] == 'group_party_timeline' ||
                        bookingData['type'] == 'large_party_timeline' ||
                        bookingData['isGroupBooking'] == true ||
                        (item['id']?.toString().startsWith('group_party_') ?? false) ||
                        (item['id']?.toString().startsWith('large_party_') ?? false);

                    if (isGroupOrLarge) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LargePartyTicketScreen(
                            booking: bookingData,
                            venue: venueMap,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DigitalTicketScreen(
                            venue: venueMap,
                            date: bookingData['bookingDate']?.toString() ?? bookingData['date']?.toString(),
                            time: bookingData['startTime']?.toString() ?? bookingData['time']?.toString(),
                            table: 'Confirmed Entry',
                            guests: (bookingData['numberOfGuests'] ?? bookingData['guestCount'] ?? 1).toString(),
                            package: 'Confirmed Entry',
                            totalPrice: bookingData['totalAmount'] != null ? '₹${bookingData['totalAmount']}' : 'PAID',
                            ticketId: (bookingData['ticketCode'] ?? bookingData['id'] ?? item['id'])?.toString(),
                            status: 'CONFIRMED',
                            booking: bookingData,
                            user: ApiService.cachedCurrentUser,
                          ),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    }
                  },
                  icon: const Icon(
                    Icons.confirmation_number_outlined,
                    size: 14,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'View Ticket',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _markAsRead(item);
                    setState(() => _navigatingCardIds.add(cardId));
                    final actor = item['actor'] ?? item['sender'];
                    final data = item['data'] is Map
                        ? Map<String, dynamic>.from(item['data'])
                        : (item['metadata'] is Map
                            ? Map<String, dynamic>.from(item['metadata'])
                            : <String, dynamic>{});
                    final partner = actor is Map
                        ? Map<String, dynamic>.from(actor)
                        : (data['user'] is Map ? Map<String, dynamic>.from(data['user']) : <String, dynamic>{});
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(user: partner),
                      ),
                    ).then((_) {
                      if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Open Chat',
                        style: TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 5. Match / Celebration Card Component ──────────────────────────────────
  Widget _buildMatchCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body =
        item['body']?.toString() ?? "You're going to the party together!";
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFCE7F3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: LunaraTheme.hotPink,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "💜 It's a Match!",
                      style: TextStyle(
                        color: LunaraTheme.hotPink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              _markAsRead(item);
              final actor = item['actor'] ?? item['sender'];
              final data = item['data'] is Map
                  ? Map<String, dynamic>.from(item['data'])
                  : (item['metadata'] is Map
                      ? Map<String, dynamic>.from(item['metadata'])
                      : <String, dynamic>{});
              final userMap = actor is Map
                  ? Map<String, dynamic>.from(actor)
                  : (data['user'] is Map ? Map<String, dynamic>.from(data['user']) : <String, dynamic>{});
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(user: userMap),
                ),
              );
            },
            icon: const Icon(
              Icons.forum_rounded,
              size: 14,
              color: Colors.white,
            ),
            label: const Text(
              "Let's Chat",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.hotPink,
              minimumSize: const Size(double.infinity, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. Ticket Ready Card Component ─────────────────────────────────────────
  Widget _buildTicketReadyCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);
    final body = item['body']?.toString() ?? 'Your digital pass is generated.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: Color(0xFF0284C7),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎟 Your Ticket is Ready',
                  style: TextStyle(
                    color: Color(0xFF0284C7),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              _markAsRead(item);
              setState(() => _navigatingCardIds.add(cardId));
              final data = item['data'] is Map
                  ? Map<String, dynamic>.from(item['data'])
                  : (item['metadata'] is Map
                      ? Map<String, dynamic>.from(item['metadata'])
                      : <String, dynamic>{});
              final bookingData = Map<String, dynamic>.from(data['booking'] is Map ? data['booking'] : data);
              final venueMap = bookingData['venue'] is Map
                  ? Map<String, dynamic>.from(bookingData['venue'])
                  : {'name': bookingData['venueName'] ?? 'Venue'};

              final isPartyPlan = bookingData['partyPlanId'] != null ||
                  bookingData['planId'] != null ||
                  data['partyPlanId'] != null ||
                  (item['id']?.toString().startsWith('party_plan_') ?? false) ||
                  (item['id']?.toString().startsWith('pp_') ?? false);

              final isStrangerMeet = bookingData['meetId'] != null ||
                  bookingData['strangersMeetId'] != null ||
                  data['meetId'] != null ||
                  (item['id']?.toString().startsWith('strangers_meet_') ?? false) ||
                  (item['id']?.toString().startsWith('meet_') ?? false);

              final isGroupOrLarge = (bookingData['numberOfGuests'] ?? bookingData['guestCount'] ?? 1) > 1 ||
                  bookingData['isGroupParty'] == true ||
                  bookingData['isLargePartyRequest'] == true ||
                  bookingData['goingMode'] == 'party_request' ||
                  bookingData['type'] == 'group_party_timeline' ||
                  bookingData['type'] == 'large_party_timeline' ||
                  bookingData['isGroupBooking'] == true ||
                  (item['id']?.toString().startsWith('group_party_') ?? false) ||
                  (item['id']?.toString().startsWith('large_party_') ?? false);

              if (isPartyPlan) {
                final planId = bookingData['partyPlanId'] ?? bookingData['planId'] ?? data['partyPlanId'] ?? '';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartyPlanTicketScreen(
                      request: item is Map ? Map<String, dynamic>.from(item) : const {},
                      plan: {'id': planId, 'venue': venueMap, ...bookingData},
                      isHost: bookingData['isHost'] == true || data['isHost'] == true,
                    ),
                  ),
                ).then((_) {
                  if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                });
              } else if (isStrangerMeet) {
                final smRequest = StrangersMeetRequest.fromJson(bookingData);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrangersMeetTicketScreen(
                      request: smRequest,
                    ),
                  ),
                ).then((_) {
                  if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                });
              } else if (isGroupOrLarge) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LargePartyTicketScreen(
                      booking: bookingData,
                      venue: venueMap,
                    ),
                  ),
                ).then((_) {
                  if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                });
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DigitalTicketScreen(
                      venue: venueMap,
                      date: bookingData['bookingDate']?.toString() ?? bookingData['date']?.toString(),
                      time: bookingData['startTime']?.toString() ?? bookingData['time']?.toString(),
                      table: 'Standard Entry',
                      guests: (bookingData['numberOfGuests'] ?? bookingData['guestCount'] ?? 1).toString(),
                      package: 'Digital Pass',
                      totalPrice: bookingData['totalAmount'] != null ? '₹${bookingData['totalAmount']}' : 'PAID',
                      ticketId: (bookingData['ticketCode'] ?? bookingData['id'] ?? item['id'])?.toString(),
                      status: 'CONFIRMED',
                      booking: bookingData,
                      user: ApiService.cachedCurrentUser,
                    ),
                  ),
                ).then((_) {
                  if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Pass',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 7. Chat Message Card Component ────────────────────────────────────────
  Widget _buildChatMessageCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body = item['body']?.toString() ?? 'Sent a message.';
    final actor = item['actor'] ?? item['sender'];
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(actor),
            child: LunaraProfileImage(
              userData: actor is Map ? Map<String, dynamic>.from(actor) : {},
              radius: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title']?.toString() ?? 'New Message',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (isUnread) _buildUnreadDot(),
        ],
      ),
    );
  }

  // ── 8. Event Reminder Card Component ───────────────────────────────────────
  Widget _buildEventReminderCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);
    final body =
        item['body']?.toString() ??
        'Your event starts tomorrow!';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE4E6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.access_time_filled_rounded,
                  color: Color(0xFFF43F5E),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Event Reminder ⏰',
                      style: TextStyle(
                        color: Color(0xFFF43F5E),
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) _buildUnreadDot(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              _markAsRead(item);
              setState(() => _navigatingCardIds.add(cardId));
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                ),
              ).then((_) {
                if (mounted) setState(() => _navigatingCardIds.remove(cardId));
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'View Event',
                  style: TextStyle(
                    color: LunaraTheme.electricViolet,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 8B. General / Booking / Meet Cancelled Card Component ────────────────
  Widget _buildCancelledCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);
    final data = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'])
        : (item['data'] is Map
              ? Map<String, dynamic>.from(item['data'])
              : <String, dynamic>{});

    final title = (item['title'] ?? 'Event Cancelled').toString();
    final body = (item['body'] ?? 'This event has been cancelled.').toString();
    final timeStr = _formatTimeAgo(item['createdAt'] ?? item['updatedAt']);
    final reason = (data['reason'] ??
            data['cancellationReason'] ??
            item['cancellationReason'] ??
            '')
        .toString();
    final bool hasRefund = data['refundAmount'] != null ||
        data['isRefunded'] == true ||
        body.toLowerCase().contains('refund') ||
        body.toLowerCase().contains('wallet');

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE4E6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cancel_outlined,
                  color: Color(0xFFE11D48),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFFE4E6)),
                          ),
                          child: const Text(
                            'CANCELLED',
                            style: TextStyle(
                              color: Color(0xFFE11D48),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 6),
                _buildUnreadDot(),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Reason: $reason',
                style: const TextStyle(
                  color: Color(0xFF9F1239),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (hasRefund) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  _markAsRead(item);
                  if (cardId.isNotEmpty) setState(() => _navigatingCardIds.add(cardId));
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LunaraWalletScreen(),
                    ),
                  ).then((_) {
                    if (mounted && cardId.isNotEmpty) setState(() => _navigatingCardIds.remove(cardId));
                  });
                },
                icon: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                label: const Text(
                  'View Refund in Wallet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 9. Expired Event / Ticket Card Component ──────────────────────────────
  Widget _buildExpiredCard(dynamic item) {
    final body = item['body']?.toString() ?? 'Event has ended.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: false,
      onTap: () => _onNotificationCardTapped(item),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_rounded,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚪ Event Completed',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              _markAsRead(item);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LunaraWalletScreen(),
                ),
              );
            },
            child: const Text(
              'History',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Like Card Component (VIP Unmasked vs Free Masked) ───────────────────────
  Widget _buildLikeCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);
    final data = item['metadata'] is Map
        ? item['metadata'] as Map<String, dynamic>
        : (item['data'] is Map
            ? item['data'] as Map<String, dynamic>
            : <String, dynamic>{});

    final bool isMasked = data['isMasked'] == true ||
        data['isMasked'] == 'true' ||
        item['isMasked'] == true ||
        item['actionType'] == 'open_vip_upgrade' ||
        item['deepLink'] == '/vip-membership';

    final actor = item['sender'] ?? item['actor'] ?? item['actorUser'];
    final actorMap = actor is Map ? Map<String, dynamic>.from(actor) : <String, dynamic>{};
    final String actorId = (actorMap['id'] ?? data['senderId'] ?? '').toString();
    final bool isActorMasked = isMasked || actorId == 'masked' || actorId.isEmpty;

    final String title = isActorMasked
        ? 'Someone likes your profile ❤️'
        : (item['title'] ?? '💖 New Connection!').toString();
    final String body = isActorMasked
        ? 'Upgrade to VIP to see who likes you'
        : (item['body'] ?? 'Liked your profile ❤️').toString();
    final String timeStr = _formatTimeAgo(item['createdAt']);

    final String senderName = (actorMap['firstName'] ?? data['senderName'] ?? 'Someone').toString();
    final String? senderPhoto = (actorMap['profileImageUrl'] ?? actorMap['profilePhotoUrl'] ?? data['senderImage'])?.toString();

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () {
        _markAsRead(item);
        if (isActorMasked) {
          setState(() => _navigatingCardIds.add(cardId));
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VIPMembershipScreen()),
          ).then((_) {
            if (mounted) setState(() => _navigatingCardIds.remove(cardId));
          });
        } else if (actorId.isNotEmpty) {
          _openUserProfile({'id': actorId, 'firstName': senderName, 'profileImageUrl': senderPhoto}, cardId);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (isActorMasked) {
                    setState(() => _navigatingCardIds.add(cardId));
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VIPMembershipScreen()),
                    ).then((_) {
                      if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                    });
                  } else if (actorId.isNotEmpty) {
                    _openUserProfile({'id': actorId, 'firstName': senderName, 'profileImageUrl': senderPhoto}, cardId);
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isActorMasked
                        ? const LinearGradient(
                            colors: [Color(0xFF2A1B38), Color(0xFF581C87)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: isActorMasked
                            ? const Color(0xFF581C87).withValues(alpha: 0.3)
                            : const Color(0xFFEC4899).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: isActorMasked
                        ? const Center(
                            child: Icon(Icons.lock_rounded, color: Color(0xFFE9D5FF), size: 20),
                          )
                        : (senderPhoto != null && senderPhoto.isNotEmpty
                            ? LunaraCachedImage(
                                ApiService.formatImageUrl(senderPhoto) ?? '',
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
                              )),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActorMasked
                                ? const Color(0xFFF3E8FF)
                                : const Color(0xFFFCE7F3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isActorMasked ? 'VIP FEATURE' : 'NEW LIKE',
                            style: TextStyle(
                              color: isActorMasked ? LunaraTheme.electricViolet : LunaraTheme.hotPink,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFF0F172A),
                        fontWeight: isUnread ? FontWeight.w900 : FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 8),
                _buildUnreadDot(),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: isActorMasked
                ? ElevatedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VIPMembershipScreen()),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(Icons.workspace_premium_rounded, size: 16, color: Colors.white),
                    label: const Text(
                      'Upgrade to VIP',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      if (actorId.isNotEmpty) {
                        _openUserProfile({'id': actorId, 'firstName': senderName, 'profileImageUrl': senderPhoto}, cardId);
                      }
                    },
                    icon: const Icon(Icons.person_rounded, size: 14, color: LunaraTheme.hotPink),
                    label: const Text(
                      'View Profile',
                      style: TextStyle(
                        color: LunaraTheme.hotPink,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: LunaraTheme.hotPink),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Super Like Card Component ─────────────────────────────────────────────
  Widget _buildSuperLikeCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final cardId = (item['id'] ?? item['entityId'] ?? '').toString();
    final bool isCardLoading = _navigatingCardIds.contains(cardId);
    final data = item['metadata'] is Map
        ? item['metadata'] as Map<String, dynamic>
        : (item['data'] is Map
            ? item['data'] as Map<String, dynamic>
            : <String, dynamic>{});

    final String title = (item['title'] ?? '⭐ Super Like!').toString();
    final String body = (item['body'] ?? 'Someone sent you a Super Like! 💜').toString();
    final String timeStr = _formatTimeAgo(item['createdAt']);

    final actor = item['sender'] ?? item['actor'] ?? item['actorUser'];
    final actorMap = actor is Map ? Map<String, dynamic>.from(actor) : <String, dynamic>{};
    final String senderId = (actorMap['id'] ?? data['senderId'] ?? '').toString();
    final String senderName = (actorMap['firstName'] ?? data['senderName'] ?? 'Someone').toString();
    final String? senderPhoto = (actorMap['profileImageUrl'] ?? actorMap['profilePhotoUrl'] ?? data['senderImage'])?.toString();

    final List postedPlans = (data['postedPlans'] is List) ? (data['postedPlans'] as List) : [];
    final Map<String, dynamic>? firstPlan = postedPlans.isNotEmpty && postedPlans.first is Map
        ? Map<String, dynamic>.from(postedPlans.first)
        : null;

    return _buildBaseCardContainer(
      isUnread: isUnread,
      isLoading: isCardLoading,
      onTap: () {
        _markAsRead(item);
        if (senderId.isNotEmpty) {
          _openUserProfile({'id': senderId, 'firstName': senderName, 'profileImageUrl': senderPhoto}, cardId);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (senderId.isNotEmpty) {
                    _openUserProfile({'id': senderId, 'firstName': senderName, 'profileImageUrl': senderPhoto}, cardId);
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFFC084FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: senderPhoto != null && senderPhoto.isNotEmpty
                        ? LunaraCachedImage(
                            ApiService.formatImageUrl(senderPhoto) ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.star_rounded, color: Colors.white, size: 22),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.star_rounded, color: Colors.white, size: 22),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SUPER LIKE',
                            style: TextStyle(
                              color: Color(0xFF8B5CF6),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: TextStyle(
                        color: const Color(0xFF0F172A),
                        fontWeight: isUnread ? FontWeight.w900 : FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 8),
                _buildUnreadDot(),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (firstPlan != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                _markAsRead(item);
                setState(() => _navigatingCardIds.add(cardId));
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                  ),
                ).then((_) {
                  if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                });
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.celebration_rounded, color: Color(0xFF8B5CF6), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "$senderName's Plan: ${firstPlan['title'] ?? firstPlan['venueName'] ?? 'Party Plan'}",
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _markAsRead(item);
                    if (senderId.isNotEmpty) {
                      _openUserProfile({'id': senderId, 'firstName': senderName, 'profileImageUrl': senderPhoto}, cardId);
                    }
                  },
                  icon: const Icon(Icons.person_rounded, size: 14, color: Color(0xFF8B5CF6)),
                  label: const Text(
                    'View Profile',
                    style: TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF8B5CF6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (firstPlan != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
                      setState(() => _navigatingCardIds.add(cardId));
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                        ),
                      ).then((_) {
                        if (mounted) setState(() => _navigatingCardIds.remove(cardId));
                      });
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white),
                    label: const Text(
                      'View Plan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Generic Card Component ────────────────────────────────────────────────
  Widget _buildGenericCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final title = item['title']?.toString() ?? 'Notification';
    final body = item['body']?.toString() ?? '';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFF3E8FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: LunaraTheme.electricViolet,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF0F172A),
                    fontWeight: isUnread ? FontWeight.w900 : FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (isUnread) ...[const SizedBox(width: 8), _buildUnreadDot()],
        ],
      ),
    );
  }

  // ── Base Container & Helpers ───────────────────────────────────────────────
  Widget _buildBaseCardContainer({
    required bool isUnread,
    required VoidCallback onTap,
    required Widget child,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isUnread ? const Color(0xFFFAF5FF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUnread
                  ? LunaraTheme.electricViolet.withValues(alpha: 0.3)
                  : const Color(0xFFF1F5F9),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              child,
              if (isLoading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            LunaraTheme.electricViolet,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDot() {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.redAccent, blurRadius: 4, spreadRadius: 1),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 200,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF94A3B8),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'All caught up!',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'New requests, matches & bookings will appear here.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
