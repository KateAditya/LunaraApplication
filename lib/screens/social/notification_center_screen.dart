import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/optimistic_action_guard.dart';
import '../../services/push_notification_service.dart';
import '../../models/user.dart';
import '../profile/profile_screen.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../widgets/top_notification_banner.dart';
import '../../widgets/upcoming_night_invite_dialog.dart';
import '../../widgets/upcoming_night_host_confirm_dialog.dart';
import 'live_feed_screen.dart';
import 'chat_screen.dart';
import 'party_plan_ticket_screen.dart';
import '../discovery/digital_ticket_screen.dart';
import '../profile/lunara_wallet_screen.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/lunara_countdown_button.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

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
  List<dynamic> _notifications = [];

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
    if (currentUid.isEmpty) return;

    try {
      final success = await ApiService.markAllNotificationsAsRead();
      if (success && mounted) {
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
    }
  }

  Future<void> _handleNotificationAction(dynamic item, String action) async {
    final notifId = item['id']?.toString();
    final currentUid = ApiService.currentUserId ?? '';

    if (notifId == null || notifId.isEmpty || currentUid.isEmpty) return;

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
          if (isCurrentTimeline && !isExistingTimeline) {
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
          final currentHostStatus = (currentData['hostPaymentStatus'] ?? '')
              .toString()
              .toLowerCase();
          final currentJoinerStatus = (currentData['joinerPaymentStatus'] ?? '')
              .toString()
              .toLowerCase();
          final isCurrentPaidOrConfirmed =
              currentPrimaryAction == 'open chat' ||
              currentPrimaryAction == 'chat' ||
              currentHostStatus == 'paid' ||
              currentJoinerStatus == 'paid' ||
              currentData['isPaid'] == true ||
              currentData['depositPaid'] == true;

          final isCurrentActivePayDeposit =
              (currentPrimaryAction == 'pay deposit' ||
                  currentPrimaryAction == 'pay now') &&
              !isCurrentPaidOrConfirmed;

          final existingPrimaryAction = (existingData['primaryAction'] ?? '')
              .toString()
              .toLowerCase();
          final existingHostStatus = (existingData['hostPaymentStatus'] ?? '')
              .toString()
              .toLowerCase();
          final existingJoinerStatus =
              (existingData['joinerPaymentStatus'] ?? '')
                  .toString()
                  .toLowerCase();
          final isExistingPaidOrConfirmed =
              existingPrimaryAction == 'open chat' ||
              existingPrimaryAction == 'chat' ||
              existingHostStatus == 'paid' ||
              existingJoinerStatus == 'paid' ||
              existingData['isPaid'] == true ||
              existingData['depositPaid'] == true;

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
      final type = (n['data']?['type'] ?? n['eventType'] ?? n['id'] ?? '')
          .toString()
          .toLowerCase();

      if (_selectedCategoryFilter == 1) {
        // PARTNER REQUESTS
        return title.contains('request') || type.contains('request');
      } else if (_selectedCategoryFilter == 2) {
        // INTERESTS
        return title.contains('interest') || type.contains('interest');
      } else if (_selectedCategoryFilter == 3) {
        // BOOKINGS
        return title.contains('booking') ||
            title.contains('confirm') ||
            type.contains('booking');
      } else if (_selectedCategoryFilter == 4) {
        // TICKETS
        return title.contains('ticket') || type.contains('ticket');
      } else if (_selectedCategoryFilter == 5) {
        // MESSAGES
        return title.contains('message') ||
            title.contains('chat') ||
            type.contains('chat');
      } else if (_selectedCategoryFilter == 6) {
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

    // ── Cancellation event routing ────────────────────────────────────
    final bool isPartyPlanCancellation =
        eventType.contains('PARTY_PLAN_CANCELLATION') ||
        type.contains('party_plan_cancellation') ||
        (item['entityType'] == 'party_plan' &&
            (eventType.contains('CANCEL') ||
             titleLower.contains('cancel') ||
             bodyLower.contains('cancel'))) ||
        ((data['partyPlanId'] != null || data['planId'] != null) &&
            (eventType.contains('CANCEL') ||
             titleLower.contains('cancel') ||
             bodyLower.contains('cancel')));

    if (isPartyPlanCancellation) {
      return _buildPartyPlanCancellationCard(item);
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
    } else if (eventType.contains('EXPIRED') ||
        titleLower.contains('completed') ||
        titleLower.contains('ended')) {
      return _buildExpiredCard(item);
    }

    return _buildGenericCard(item);
  }

  void _openUserProfile(dynamic actorData) {
    if (actorData == null) return;
    Map<String, dynamic> userMap = {};
    if (actorData is Map) {
      userMap = Map<String, dynamic>.from(actorData);
    } else if (actorData is String && actorData.trim().isNotEmpty) {
      userMap = {'id': actorData.trim()};
    }

    if (userMap.isEmpty) return;

    final uid =
        userMap['id']?.toString() ??
        userMap['userId']?.toString() ??
        userMap['_id']?.toString() ??
        userMap['actorUserId']?.toString() ??
        '';
    if (uid.isEmpty) return;

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

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfileScreen(user: userObj)),
    );
  }

  void _onNotificationCardTapped(dynamic item) {
    _markAsRead(item);
    if (item == null) return;
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
    PushNotificationService.navigateFromPayload(payload);
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

  void _openUpcomingNightHostConfirm(dynamic item) {
    final payloadData = item['data'] is Map
        ? Map<String, dynamic>.from(item['data'])
        : (item['metadata'] is Map
              ? Map<String, dynamic>.from(item['metadata'])
              : <String, dynamic>{});
    final matchId =
        payloadData['matchId']?.toString() ??
        item['entityId']?.toString() ??
        '';
    final actor = item['actor'] ?? item['sender'];
    final partnerName = actor is Map
        ? (actor['firstName'] ?? actor['name'] ?? 'Partner')
        : 'Partner';
    final partnerPhoto = actor is Map
        ? (actor['profilePhotoUrl'] ?? actor['primaryPhoto'])
        : null;
    final venueName = payloadData['venueName']?.toString() ?? 'Venue';
    final date = payloadData['eventDate']?.toString() ?? 'Tonight';
    final time = payloadData['eventTime']?.toString() ?? '20:00';

    showDialog(
      context: context,
      builder: (_) => UpcomingNightHostConfirmDialog(
        matchId: matchId,
        partnerName: partnerName,
        partnerPhoto: partnerPhoto,
        venueName: venueName,
        date: date,
        time: time,
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

    return _buildBaseCardContainer(
      isUnread: isUnread,
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
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
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
                        await _startHostRazorpayDirectPayment(
                          partyPlanId: partyPlanId,
                          venueName: venueName,
                          orderId: hostRazorpayOrderId,
                          depositAmount: depositAmount,
                          onSuccess: () async {
                            await _fetchNotifications();
                          },
                        );
                      },
                      icon: const Icon(
                        Icons.payment_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      label: Text(
                        'Pay Deposit (${depositAmount.toStringAsFixed(0)})',
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
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
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

    final String joinerPaymentStatus =
        (data['joinerPaymentStatus'] ??
                data['paymentStatus'] ??
                item['joinerPaymentStatus'] ??
                item['paymentStatus'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();

    final bool isPaid =
        data['isPaid'] == true ||
        item['isPaid'] == true ||
        data['depositPaid'] == true ||
        item['depositPaid'] == true ||
        data['guestPaid'] == true ||
        item['guestPaid'] == true ||
        joinerPaymentStatus == 'paid' ||
        joinerPaymentStatus == 'completed';

    final String primaryAction =
        (data['primaryAction'] ?? item['primaryAction'] ?? '')
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

    final bool isChatAction =
        primaryAction == 'open chat' ||
        primaryAction == 'chat' ||
        data['chatUnlocked'] == true ||
        item['chatUnlocked'] == true ||
        data['isConfirmed'] == true ||
        item['isConfirmed'] == true;

    final bool isDepositPaid =
        isPaid ||
        isChatAction ||
        lifecycleStatus == 'match_confirmed' ||
        lifecycleStatus == 'chat_enabled' ||
        lifecycleStatus == 'guest_payment_completed' ||
        lifecycleStatus == 'completed' ||
        lifecycleStatus == 'confirmed' ||
        lifecycleStatus == 'paid' ||
        currentStatus.contains('match confirmed') ||
        currentStatus.contains('completed');

    final actor = item['actor'] ?? item['sender'] ?? item['actorUser'];
    final actorId =
        (actor is Map ? (actor['id'] ?? actor['userId']) : null)?.toString() ??
        '';
    final actorName =
        (actor is Map
                ? (actor['firstName'] ?? actor['name'] ?? 'Partner')
                : 'Partner')
            .toString();

    return _buildBaseCardContainer(
      isUnread: isUnread,
      onTap: () => _onNotificationCardTapped(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDepositPaid
                      ? const Color(0xFFE0E7FF)
                      : const Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDepositPaid
                      ? Icons.forum_rounded
                      : Icons.check_circle_rounded,
                  color: isDepositPaid
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
                      isDepositPaid ? 'MATCH CONFIRMED' : 'ACTION REQUIRED',
                      style: TextStyle(
                        color: isDepositPaid
                            ? LunaraTheme.electricViolet
                            : const Color(0xFF10B981),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      isDepositPaid
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
            isDepositPaid
                ? 'Your safety deposit is paid! Chat is unlocked.'
                : body,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (isDepositPaid)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _markAsRead(item);
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
                      );
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PartyPlanTicketScreen(
                            request: item,
                            plan: {'id': partyPlanId, ...data},
                            isHost: false,
                          ),
                        ),
                      );
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartyPlanTicketScreen(
                                  request: const {},
                                  plan: {'id': planId, 'venue': {'name': venueName}},
                                  isHost: false,
                                ),
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _handleNotificationAction(item, 'DECLINE'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Icon(
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LunaraWalletScreen(),
                    ),
                  );
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
          else if (isRecipient && requestId.isNotEmpty && planId.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      if (!OptimisticActionGuard.start('NOTIF_CANCEL_KEEP:$planId:$requestId')) return;
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Cancellation request declined. Party Plan remains active.'),
                          backgroundColor: Colors.grey.shade800,
                        ),
                      );
                      try {
                        await ApiService.respondToPartyPlanCancellationRequest(
                          planId: planId,
                          requestId: requestId,
                          action: 'reject',
                        );
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } finally {
                        OptimisticActionGuard.end('NOTIF_CANCEL_KEEP:$planId:$requestId');
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
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
                    onPressed: () async {
                      if (!OptimisticActionGuard.start('NOTIF_CANCEL_APPROVE:$planId:$requestId')) return;
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Party Plan cancelled. Commitment deposits credited to wallets!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      try {
                        await ApiService.respondToPartyPlanCancellationRequest(
                          planId: planId,
                          requestId: requestId,
                          action: 'approve',
                        );
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } finally {
                        OptimisticActionGuard.end('NOTIF_CANCEL_APPROVE:$planId:$requestId');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'CONFIRM CANCELLATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      _markAsRead(item);
                      if (requestId.isNotEmpty) {
                        final res = await ApiService.acceptPartyPlanInvite(
                          requestId,
                        );
                        if (mounted) {
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
                    child: const Text(
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
                    onPressed: () {
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
                  onPressed: () => _handleNotificationAction(item, 'DECLINE'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    backgroundColor: const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 38),
                  ),
                  child: const Row(
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
                    onPressed: () => _handleNotificationAction(item, 'ACCEPT_CANCELLATION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE11D48),
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
                  onPressed: () => _handleNotificationAction(item, 'REJECT_CANCELLATION'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    backgroundColor: const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 38),
                  ),
                  child: const Row(
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
    final actor = item['actor'] ?? item['sender'];
    final actorName = actor?['firstName'] ?? actor?['name'] ?? 'User';
    final body = item['body']?.toString() ?? 'You are going together!';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
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
          ElevatedButton.icon(
            onPressed: () {
              _markAsRead(item);
              _openUpcomingNightHostConfirm(item);
            },
            icon: const Icon(
              Icons.payment_rounded,
              size: 14,
              color: Colors.white,
            ),
            label: const Text(
              "Confirm Booking & Pay",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
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

  // ── 4. Booking Confirmed Card Component ────────────────────────────────────
  Widget _buildBookingConfirmedCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
    final body =
        item['body']?.toString() ??
        'Your booking is confirmed. Get ready for the party!';
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
                    final data = item['data'] is Map
                        ? Map<String, dynamic>.from(item['data'])
                        : (item['metadata'] is Map
                            ? Map<String, dynamic>.from(item['metadata'])
                            : <String, dynamic>{});
                    final bookingData = Map<String, dynamic>.from(data['booking'] is Map ? data['booking'] : data);
                    final venueMap = bookingData['venue'] is Map
                        ? Map<String, dynamic>.from(bookingData['venue'])
                        : {'name': bookingData['venueName'] ?? 'Venue'};
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
                    );
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
                    );
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
    final body = item['body']?.toString() ?? 'Your digital pass is generated.';
    final timeStr = _formatTimeAgo(item['createdAt']);

    return _buildBaseCardContainer(
      isUnread: isUnread,
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
              final data = item['data'] is Map
                  ? Map<String, dynamic>.from(item['data'])
                  : (item['metadata'] is Map
                      ? Map<String, dynamic>.from(item['metadata'])
                      : <String, dynamic>{});
              final bookingData = Map<String, dynamic>.from(data['booking'] is Map ? data['booking'] : data);
              final venueMap = bookingData['venue'] is Map
                  ? Map<String, dynamic>.from(bookingData['venue'])
                  : {'name': bookingData['venueName'] ?? 'Venue'};
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
              );
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
    final body =
        item['body']?.toString() ??
        'Your Stranger Meet starts tomorrow at 8:00 PM';
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                ),
              );
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

  // ── Super Like Card Component ─────────────────────────────────────────────
  Widget _buildSuperLikeCard(dynamic item) {
    final bool isUnread = !(item['isRead'] == true || item['read'] == true);
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
      onTap: () {
        _markAsRead(item);
        if (senderId.isNotEmpty) {
          _openUserProfile({'id': senderId, 'firstName': senderName, 'profileImageUrl': senderPhoto});
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
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
                      ? Image.network(
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
            Container(
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
                ],
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
                      _openUserProfile({'id': senderId, 'firstName': senderName, 'profileImageUrl': senderPhoto});
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveFeedScreen(initialTabIndex: 1),
                        ),
                      );
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
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
          child: child,
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
