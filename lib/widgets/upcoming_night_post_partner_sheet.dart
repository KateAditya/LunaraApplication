// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/top_notification_banner.dart';
import '../widgets/dialogs/time_lock_blocked_dialog.dart';
import '../utils/lunara_date_formatter.dart';
import 'lunara_cached_image.dart';
import 'lunara_profile_image.dart';
import 'smart_checkout_sheet.dart';

class UpcomingNightPostPartnerSheet extends StatefulWidget {
  final Map<String, dynamic> party;
  final String venueId;
  final String venueName;
  final String date;
  final String time;
  final String? bannerImage;
  final String? eventTitle;

  const UpcomingNightPostPartnerSheet({
    super.key,
    required this.party,
    required this.venueId,
    required this.venueName,
    required this.date,
    required this.time,
    this.bannerImage,
    this.eventTitle,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> party,
    required String venueId,
    required String venueName,
    required String date,
    required String time,
    String? bannerImage,
    String? eventTitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: UpcomingNightPostPartnerSheet(
          party: party,
          venueId: venueId,
          venueName: venueName,
          date: date,
          time: time,
          bannerImage: bannerImage,
          eventTitle: eventTitle,
        ),
      ),
    );
  }

  @override
  State<UpcomingNightPostPartnerSheet> createState() => _UpcomingNightPostPartnerSheetState();
}

class _UpcomingNightPostPartnerSheetState extends State<UpcomingNightPostPartnerSheet> {
  late TextEditingController _messageController;
  final TextEditingController _inviteeSearchController = TextEditingController();
  bool _isPosting = false;
  String _selectedPrivacy = 'PUBLIC'; // 'PUBLIC', 'PRIVATE' or 'BOTH'
  // SELF_PAY: the host buys both tickets now. SPLIT: the host buys one and the
  // person who joins buys the other when their request is accepted.
  String _selectedPaymentType = 'self_pay';
  final List<String> _selectedUserIds = [];
  String _selectedFoodPref = 'ANY'; // 'ANY', 'VEG', 'NON_VEG'
  String _selectedDrinkPref = 'COCKTAILS'; // 'COCKTAILS', 'BEER', 'NON_ALCOHOLIC', 'ANY'

  List<Map<String, dynamic>> _candidateInvitees = [];
  bool _isLoadingInvitees = false;

  late Razorpay _razorpay;
  String? _pendingPlanId;
  String? _pendingOrderId;
  double? _pendingAmount;
  bool _isHybridFlow = false;

  @override
  void initState() {
    super.initState();
    final title = widget.eventTitle ?? widget.party['title'] ?? widget.party['name'] ?? widget.venueName;
    _messageController = TextEditingController(
      text: "Looking for a fun party partner for $title at ${widget.venueName}! ✨ Let's vibe!",
    );
    _loadInvitees();
    if (!kIsWeb) {
      try {
        _razorpay = Razorpay();
        _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
        _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
        _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
      } catch (e) {
        debugPrint('Razorpay init error in UpcomingNightPostPartnerSheet: $e');
      }
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      try {
        _razorpay.clear();
      } catch (e) {
        debugPrint('Razorpay clear error: $e');
      }
    }
    _messageController.dispose();
    _inviteeSearchController.dispose();
    super.dispose();
  }

  void _onPostSuccess() {
    if (!mounted) return;
    ApiService.planPostedNotifier.value++;
    ApiService.notifyFeedNeedsRefresh();

    Navigator.pop(context, true);
    ApiService.switchDashboardTab(1);

    TopNotificationBanner.show(
      title: 'Partner Search Posted! 🚀',
      body: 'Your Upcoming Night post is now live on the Live Feed! Anyone interested can request to join you.',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Posted to Live Feed! ✨'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) async {
    final userId = ApiService.currentUserId;
    if (_pendingPlanId == null || userId == null) return;

    if (_isHybridFlow) {
      _isHybridFlow = false;
      try {
        await ApiService.verifyWalletRecharge(
          amount: _pendingAmount ?? 0.0,
          razorpayPaymentId: response.paymentId ?? '',
          razorpayOrderId: response.orderId ?? _pendingOrderId ?? '',
          razorpaySignature: response.signature ?? '',
        );

        final payRes = await ApiService.payWithWallet(
          amount: _hostPaysNow,
          planId: _pendingPlanId!,
          paymentType: 'party_partner_post',
        );

        if (payRes != null && payRes['success'] == true) {
          final transactionId = payRes['data']?['transactionId']?.toString() ?? 'wallet';
          final confirmRes = await ApiService.post(
            '/api/mobile/party-plans/$_pendingPlanId/host-pay',
            body: {
              'userId': userId,
              'razorpay_order_id': 'order_mock_wallet_$_pendingPlanId',
              'razorpay_payment_id': 'wallet_$transactionId',
              'razorpay_signature': 'mock_signature',
            },
          );
          if (confirmRes.statusCode == 200) {
            _onPostSuccess();
            return;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recharge succeeded. Please tap to complete payment with wallet.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Hybrid post completion error: $e');
      }
      return;
    }

    try {
      final confirmRes = await ApiService.post(
        '/api/mobile/party-plans/$_pendingPlanId/host-pay',
        body: {
          'userId': userId,
          'razorpay_order_id': response.orderId ?? _pendingOrderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        },
      );
      if (confirmRes.statusCode == 200) {
        _onPostSuccess();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment verification failed. Please check your plans.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Direct gateway host-pay error: $e');
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    _isHybridFlow = false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment Failed: ${response.message ?? "Transaction Cancelled"}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('External Wallet: ${response.walletName}'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  Future<void> _loadInvitees([String? query]) async {
    setState(() => _isLoadingInvitees = true);
    try {
      List<Map<String, dynamic>> results = await ApiService.fetchAvailableInvitees(
        venueId: widget.venueId,
        date: widget.date,
        search: query,
      );

      // If results are empty, gracefully fall back to active profiles so user never sees an empty list
      if (results.isEmpty) {
        try {
          final customers = await ApiService.fetchCustomers();
          final currentUserId = ApiService.currentUserId;
          if (customers.isNotEmpty) {
            results = customers
                .where((u) => u['id']?.toString() != currentUserId)
                .where((u) {
                  if (query == null || query.trim().isEmpty) return true;
                  final q = query.trim().toLowerCase();
                  final name = '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.toLowerCase();
                  final city = (u['city'] ?? '').toString().toLowerCase();
                  return name.contains(q) || city.contains(q);
                })
                .map((u) => {
                      'userId': u['id']?.toString(),
                      'firstName': u['firstName'] ?? 'User',
                      'age': u['age'],
                      'city': u['city'] ?? 'Pune',
                      'gender': u['gender'],
                      'bio': u['bio'] ?? '',
                      'primaryPhoto': u['profilePhotoUrl'] ?? u['profilePhoto'] ?? u['photoUrl'],
                      'isVerified': u['isVerified'] == true,
                      'compatibilityScore': 90,
                      'isInterested': false,
                    })
                .toList();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _candidateInvitees = results;
        _isLoadingInvitees = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingInvitees = false);
    }
  }

  void _toggleUserSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  void _selectAllInvitees() {
    setState(() {
      for (final item in _candidateInvitees) {
        final id = item['userId']?.toString();
        if (id != null && id.isNotEmpty && !_selectedUserIds.contains(id)) {
          _selectedUserIds.add(id);
        }
      }
    });
  }

  void _clearAllInvitees() {
    setState(() {
      _selectedUserIds.clear();
    });
  }

  /// The event's ticket price, per person. The server resolves this again from
  /// the event row before charging anything — this copy only drives the
  /// breakdown the host sees before they commit.
  double get _entryPrice {
    // Only ever the event's own price. `price` is deliberately not consulted:
    // the Event Posts feed substitutes venue cover charges into it when an event
    // has none, and quoting that would show the host a figure the server would
    // never charge.
    final raw = widget.party['entryPrice'] ?? widget.party['rawAd']?['entryPrice'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  bool get _isFreeEvent => _entryPrice <= 0;

  /// What the host pays now: both tickets on SELF_PAY, just theirs on SPLIT.
  double get _hostPaysNow =>
      _isFreeEvent ? 0.0 : _entryPrice * (_selectedPaymentType == 'self_pay' ? 2 : 1);

  String _money(double v) =>
      '₹${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)}';

  String _formatDisplayDate(String rawDate) {
    try {
      final dt = LunaraDateFormatter.parseToLocal(rawDate);
      if (dt != null) {
        return DateFormat('EEEE, dd MMM yyyy').format(dt);
      }
      return rawDate;
    } catch (_) {
      return rawDate;
    }
  }

  String _formatToIsoDateTime(String dateStr, String timeStr) {
    try {
      DateTime? parsedDate = LunaraDateFormatter.parseToLocal(dateStr);
      if (parsedDate == null) {
        if (dateStr.contains('T')) {
          parsedDate = DateTime.tryParse(dateStr);
        } else {
          final ymdMatch = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(dateStr);
          if (ymdMatch != null) {
            parsedDate = DateTime(
              int.parse(ymdMatch.group(1)!),
              int.parse(ymdMatch.group(2)!),
              int.parse(ymdMatch.group(3)!),
            );
          } else {
            final dmyMatch = RegExp(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(dateStr);
            if (dmyMatch != null) {
              parsedDate = DateTime(
                int.parse(dmyMatch.group(3)!),
                int.parse(dmyMatch.group(2)!),
                int.parse(dmyMatch.group(1)!),
              );
            }
          }
        }
      }

      if (parsedDate == null) {
        final rawPartyDate = widget.party['eventDate'] ??
            widget.party['rawDate'] ??
            widget.party['fromDate'] ??
            widget.party['toDate'] ??
            widget.party['bannerFromDate'] ??
            widget.party['date'];
        if (rawPartyDate != null && rawPartyDate.toString() != dateStr) {
          parsedDate = LunaraDateFormatter.parseToLocal(rawPartyDate);
        }
      }

      final effectiveDate = parsedDate ?? DateTime.now();

      int hour = 20;
      int minute = 0;

      final cleanTime = timeStr.trim().toUpperCase();
      if (cleanTime.contains('PM') || cleanTime.contains('AM')) {
        final isPm = cleanTime.contains('PM');
        final digits = cleanTime.replaceAll(RegExp(r'[^0-9:]'), '');
        final timeParts = digits.split(':');
        hour = int.tryParse(timeParts[0]) ?? (isPm ? 8 : 20);
        if (isPm && hour < 12) hour += 12;
        if (!isPm && hour == 12) hour = 0;
        if (timeParts.length > 1) {
          minute = int.tryParse(timeParts[1]) ?? 0;
        }
      } else if (cleanTime.contains(':')) {
        final timeParts = cleanTime.split(':');
        hour = int.tryParse(timeParts[0]) ?? 20;
        minute = int.tryParse(timeParts[1]) ?? 0;
      }

      final combined = DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
        hour,
        minute,
      );
      return combined.toUtc().toIso8601String();
    } catch (e) {
      debugPrint('Error in _formatToIsoDateTime: $e');
      return DateTime.now().add(const Duration(hours: 3)).toUtc().toIso8601String();
    }
  }

  Future<void> _submitPost() async {
    final userId = ApiService.currentUserId;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to post to Live Feed')),
      );
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a message for your partner search')),
      );
      return;
    }

    // An invite-only or both plan with no one invited cannot be joined via invites, so
    // it is refused here rather than posted into a dead end.
    if ((_selectedPrivacy == 'PRIVATE' || _selectedPrivacy == 'BOTH') && _selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one person to invite, or switch to Public Feed.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isoPlanDateTime = _formatToIsoDateTime(widget.date, widget.time);
    final dt = DateTime.tryParse(isoPlanDateTime);
    if (dt != null) {
      final now = DateTime.now().toUtc();
      final diff = dt.difference(now);
      if (diff.inMinutes < 240) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Partner searches for upcoming night events must be posted at least 4 hours before event start time.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isPosting = true);

    try {
      // The same event reaches this sheet under three different key names
      // depending on where it came from: `adId` from the Event Posts feed,
      // `eventId` from the Discovery upcoming-nights strip, and a raw `id` from
      // the venue screen's ad payload. The server needs the event's real id to
      // resolve its price and hold its seats, so all three are accepted and the
      // `ad_event_` prefix the feed adds is stripped.
      final rawAdId = (widget.party['adId'] ??
              widget.party['eventId'] ??
              widget.party['upcomingNightId'] ??
              widget.party['rawAd']?['id'] ??
              widget.party['id'])
          ?.toString();
      final adId = (rawAdId ?? '').replaceFirst(RegExp(r'^ad_event_'), '');

      if (adId.isEmpty) {
        setState(() => _isPosting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not identify this event. Please reopen it and try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final flyer = widget.bannerImage ??
          widget.party['bannerUrl'] ??
          widget.party['bannerImage'] ??
          widget.party['posterUrl'] ??
          widget.party['flyer'] ??
          widget.party['imageUrl'] ??
          widget.party['coverImageUrl'] ??
          widget.party['image'] ??
          widget.party['imagePath'];

      final eventTitle = widget.eventTitle ??
          widget.party['title'] ??
          widget.party['name'] ??
          widget.party['eventTitle'] ??
          widget.venueName;

      final response = await ApiService.post(
        '/api/mobile/party-plans',
        body: {
          'userId': userId,
          'venueId': widget.venueId,
          'venueName': widget.venueName,
          'message': _messageController.text.trim(),
          'planDateTime': isoPlanDateTime,
          'privacyType': _selectedPrivacy.toLowerCase(),
          'paymentStatus': _hostPaysNow > 0 ? 'pending' : 'paid',
          'paymentType': _selectedPaymentType,
          'selectedUserIds': _selectedUserIds,
          'mobileNumber': '',
          'optionalMobileNumber': '',
          'foodPreference': _selectedFoodPref,
          'drinkPreference': _selectedDrinkPref,
          'showVenueDetails': true,
          'showDateDetails': true,
          'showHostName': true,
          'showProfilePhoto': true,
          'isUpcomingNight': true,
          'upcomingNightId': adId,
          'adId': adId,
          'bannerToDate': widget.party['bannerToDate'] ?? widget.party['toDate'],
          'imageUrl': flyer,
          'coverImageUrl': flyer,
          'bannerUrl': flyer,
          'posterUrl': flyer,
          'flyer': flyer,
          'eventTitle': eventTitle,
          'title': eventTitle,
          'entryPrice': _entryPrice,
          'totalAmount': _hostPaysNow,
          'depositAmount': _hostPaysNow,
          'amountPaid': _hostPaysNow,
        },
        timeout: const Duration(seconds: 25),
      );

      setState(() => _isPosting = false);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        final planData = body['data'] ?? body['partyPlan'] ?? body;
        final String planId = (planData['id'] ?? body['id'] ?? '').toString();
        final String razorpayOrderId = (body['razorpayOrderId'] ??
                planData['hostRazorpayOrderId'] ??
                'order_mock_${DateTime.now().millisecondsSinceEpoch}')
            .toString();
        final String razorpayKeyId = (body['razorpayKeyId'] ?? 'rzp_test_123').toString();

        if (_hostPaysNow > 0 && planId.isNotEmpty) {
          final double amountToPay = _hostPaysNow;
          final bool? sheetSuccess = await SmartCheckoutSheet.show(
            context: context,
            title: 'Confirm & Post to Live Feed',
            subtitle:
                '${_selectedPaymentType == 'self_pay' ? "I'll pay for both tickets" : "Split Ticket (My Share)"} for $eventTitle',
            itemPrice: amountToPay,
            onWalletPayment: () async {
              try {
                final payRes = await ApiService.payWithWallet(
                  amount: amountToPay,
                  planId: planId,
                  paymentType: 'party_partner_post',
                );
                if (payRes != null && payRes['success'] == true) {
                  final transactionId = payRes['data']?['transactionId']?.toString() ?? 'wallet';
                  final confirmRes = await ApiService.post(
                    '/api/mobile/party-plans/$planId/host-pay',
                    body: {
                      'userId': userId,
                      'razorpay_order_id': 'order_mock_wallet_$planId',
                      'razorpay_payment_id': 'wallet_$transactionId',
                      'razorpay_signature': 'mock_signature',
                    },
                  );
                  return confirmRes.statusCode == 200;
                }
                return false;
              } catch (err) {
                debugPrint('Wallet host-pay error: $err');
                return false;
              }
            },
            onDirectPayment: () async {
              _pendingPlanId = planId;
              _pendingOrderId = razorpayOrderId;
              _pendingAmount = amountToPay;
              _isHybridFlow = false;

              final isMock = kIsWeb ||
                  razorpayOrderId.isEmpty ||
                  razorpayOrderId.startsWith('order_mock_') ||
                  razorpayKeyId == 'rzp_test_123';

              if (isMock) {
                try {
                  final confirmRes = await ApiService.post(
                    '/api/mobile/party-plans/$planId/host-pay',
                    body: {
                      'userId': userId,
                      'razorpay_order_id': razorpayOrderId,
                      'razorpay_payment_id': 'pay_${DateTime.now().millisecondsSinceEpoch}',
                      'razorpay_signature': 'mock_signature',
                    },
                  );
                  return confirmRes.statusCode == 200;
                } catch (err) {
                  debugPrint('Direct host-pay error: $err');
                  return false;
                }
              }

              final options = {
                'key': razorpayKeyId,
                'amount': (amountToPay * 100).toInt(),
                'name': 'Lunara',
                'description': 'Post to Live Feed: $eventTitle',
                'order_id': razorpayOrderId.isNotEmpty ? razorpayOrderId : null,
                'timeout': 300,
                'theme': {'color': '#7c3aed'},
              };

              try {
                _razorpay.open(options);
                return 'gateway_launched';
              } catch (rzpErr) {
                debugPrint('Razorpay open error: $rzpErr');
                final confirmRes = await ApiService.post(
                  '/api/mobile/party-plans/$planId/host-pay',
                  body: {
                    'userId': userId,
                    'razorpay_order_id': razorpayOrderId,
                    'razorpay_payment_id': 'pay_${DateTime.now().millisecondsSinceEpoch}',
                    'razorpay_signature': 'mock_signature',
                  },
                );
                return confirmRes.statusCode == 200;
              }
            },
            onHybridPayment: (shortfallAmount) async {
              _pendingPlanId = planId;
              _pendingAmount = shortfallAmount;
              _isHybridFlow = true;

              final isMock = kIsWeb;
              if (isMock) {
                try {
                  await ApiService.verifyWalletRecharge(
                    amount: shortfallAmount,
                    razorpayPaymentId: 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
                    razorpayOrderId: 'order_mock_${DateTime.now().millisecondsSinceEpoch}',
                    razorpaySignature: 'mock_signature',
                  );
                  final payRes = await ApiService.payWithWallet(
                    amount: amountToPay,
                    planId: planId,
                    paymentType: 'party_partner_post',
                  );
                  if (payRes != null && payRes['success'] == true) {
                    final transactionId = payRes['data']?['transactionId']?.toString() ?? 'wallet';
                    final confirmRes = await ApiService.post(
                      '/api/mobile/party-plans/$planId/host-pay',
                      body: {
                        'userId': userId,
                        'razorpay_order_id': 'order_mock_wallet_$planId',
                        'razorpay_payment_id': 'wallet_$transactionId',
                        'razorpay_signature': 'mock_signature',
                      },
                    );
                    return confirmRes.statusCode == 200;
                  }
                  return false;
                } catch (err) {
                  debugPrint('Hybrid host-pay mock error: $err');
                  return false;
                }
              }

              final orderData = await ApiService.createWalletRechargeOrder(shortfallAmount);
              if (orderData != null) {
                final String orderId = orderData['orderId'] ?? orderData['id'] ?? '';
                _pendingOrderId = orderId;
                final options = {
                  'key': orderData['keyId'] ?? razorpayKeyId,
                  'amount': (shortfallAmount * 100).toInt(),
                  'name': 'Lunara Wallet Recharge',
                  'description': 'Shortfall ₹${shortfallAmount.toStringAsFixed(0)} for $eventTitle',
                  'order_id': orderId.isNotEmpty ? orderId : null,
                  'timeout': 300,
                  'theme': {'color': '#7c3aed'},
                };
                try {
                  _razorpay.open(options);
                  return 'gateway_launched';
                } catch (e) {
                  debugPrint('Hybrid Razorpay error: $e');
                  return false;
                }
              }
              return false;
            },
          );

          if (sheetSuccess == true) {
            _onPostSuccess();
            return;
          }

          if (sheetSuccess != null && sheetSuccess == false && !_isHybridFlow) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment cancelled. Your post is saved as unpaid and not yet live on the feed.'),
                backgroundColor: Colors.amber,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          return;
        }

        _onPostSuccess();
      } else {
        final body = jsonDecode(response.body);
        final msg = body['message'] ?? 'Failed to create partner search post.';
        final isTimeLock = TimeLockBlockedDialog.isConflictError(msg) ||
            body['code'] == 'FOUR_HOUR_TIME_LOCK' ||
            body['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
            body['code'] == 'PLAN_TIME_LOCKED' ||
            body['reason'] == 'PLAN_TIME_LOCKED' ||
            body['code'] == 'USER_ALREADY_HAS_PLAN';

        if (isTimeLock) {
          TimeLockBlockedDialog.show(
            context,
            errorData: body is Map<String, dynamic> ? Map<String, dynamic>.from(body) : {'message': msg},
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isPosting = false);
      if (TimeLockBlockedDialog.isConflictError(e)) {
        TimeLockBlockedDialog.showWithMessage(context, e.toString());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.eventTitle ?? widget.party['title'] ?? widget.party['name'] ?? widget.venueName;
    final flyer = widget.bannerImage ?? widget.party['image'] ?? widget.party['coverImageUrl'] ?? widget.party['imagePath'];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14141E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POST TO FIND PARTNER',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        'Post this upcoming night to Live Feed to find a partner',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 20),

          // Scrollable Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Card Preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2C) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (flyer != null && flyer.toString().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: LunaraCachedImage(
                              flyer.toString().startsWith('http')
                                  ? flyer.toString()
                                  : '${ApiService.baseUrl}${flyer.toString().startsWith('/') ? '' : '/'}${flyer.toString()}',
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 64,
                                height: 64,
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                                child: const Icon(Icons.nightlife_rounded, color: LunaraTheme.electricViolet),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.nightlife_rounded, color: LunaraTheme.electricViolet),
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.venueName,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today_rounded, size: 12, color: LunaraTheme.electricViolet),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDisplayDate(widget.date),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: LunaraTheme.electricViolet,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.access_time_rounded, size: 12, color: LunaraTheme.hotPink),
                                  const SizedBox(width: 4),
                                  Text(
                                    LunaraDateFormatter.normalizeTimeTo12Hour(widget.time),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: LunaraTheme.hotPink,
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
                  const SizedBox(height: 18),

                  // Message / Note
                  const Text(
                    'CUSTOMIZE YOUR INVITATION MESSAGE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
                      hintText: 'Add details about your vibe or what you are looking for...',
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[400], fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: LunaraTheme.electricViolet, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Food Preference
                  const Text(
                    'FOOD PREFERENCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildPillOption('ANY', 'Any Food', _selectedFoodPref == 'ANY', () {
                        setState(() => _selectedFoodPref = 'ANY');
                      }, isDark),
                      const SizedBox(width: 8),
                      _buildPillOption('VEG', 'Veg Only 🥦', _selectedFoodPref == 'VEG', () {
                        setState(() => _selectedFoodPref = 'VEG');
                      }, isDark),
                      const SizedBox(width: 8),
                      _buildPillOption('NON_VEG', 'Non-Veg 🍗', _selectedFoodPref == 'NON_VEG', () {
                        setState(() => _selectedFoodPref = 'NON_VEG');
                      }, isDark),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Drink Preference
                  const Text(
                    'DRINK PREFERENCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPillOption('COCKTAILS', 'Cocktails 🍸', _selectedDrinkPref == 'COCKTAILS', () {
                        setState(() => _selectedDrinkPref = 'COCKTAILS');
                      }, isDark),
                      _buildPillOption('BEER', 'Beer 🍺', _selectedDrinkPref == 'BEER', () {
                        setState(() => _selectedDrinkPref = 'BEER');
                      }, isDark),
                      _buildPillOption('NON_ALCOHOLIC', 'Non-Alcoholic 🧃', _selectedDrinkPref == 'NON_ALCOHOLIC', () {
                        setState(() => _selectedDrinkPref = 'NON_ALCOHOLIC');
                      }, isDark),
                      _buildPillOption('ANY', 'Any', _selectedDrinkPref == 'ANY', () {
                        setState(() => _selectedDrinkPref = 'ANY');
                      }, isDark),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Privacy Option
                  const Text(
                    'VISIBILITY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPrivacyCard(
                          title: 'Public Feed',
                          subtitle: 'Anyone can request to join',
                          isSelected: _selectedPrivacy == 'PUBLIC',
                          onTap: () => setState(() => _selectedPrivacy = 'PUBLIC'),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildPrivacyCard(
                          title: 'Invite Only',
                          subtitle: 'Only people you invite',
                          isSelected: _selectedPrivacy == 'PRIVATE',
                          onTap: () {
                            setState(() => _selectedPrivacy = 'PRIVATE');
                            if (_candidateInvitees.isEmpty && !_isLoadingInvitees) {
                              _loadInvitees();
                            }
                          },
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildPrivacyCard(
                          title: 'Both',
                          subtitle: 'Public + direct invites',
                          isSelected: _selectedPrivacy == 'BOTH',
                          onTap: () {
                            setState(() => _selectedPrivacy = 'BOTH');
                            if (_candidateInvitees.isEmpty && !_isLoadingInvitees) {
                              _loadInvitees();
                            }
                          },
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),

                  // ── Profile selection for Invite-Only and Both ──────────────
                  if (_selectedPrivacy != 'PUBLIC') ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'SELECT PEOPLE TO INVITE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const Spacer(),
                        if (_selectedUserIds.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_selectedUserIds.length} Selected',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: LunaraTheme.electricViolet,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _clearAllInvitees,
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ] else if (_candidateInvitees.isNotEmpty) ...[
                          GestureDetector(
                            onTap: _selectAllInvitees,
                            child: const Text(
                              'Select All',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: LunaraTheme.electricViolet,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Invitee Search Bar
                    TextField(
                      controller: _inviteeSearchController,
                      onChanged: (val) => _loadInvitees(val),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search people by name or city...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey[400],
                          fontSize: 12.5,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: LunaraTheme.electricViolet),
                        suffixIcon: _inviteeSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _inviteeSearchController.clear();
                                  _loadInvitees();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: LunaraTheme.electricViolet, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Invitee Profiles List Box
                    _buildInviteesSection(isDark),

                    const SizedBox(height: 8),

                    // Status / Guidance banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedUserIds.isEmpty
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.10)
                            : const Color(0xFF10B981).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedUserIds.isEmpty
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                              : const Color(0xFF10B981).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedUserIds.isEmpty
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 16,
                            color: _selectedUserIds.isEmpty
                                ? const Color(0xFFB45309)
                                : const Color(0xFF059669),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedUserIds.isEmpty
                                  ? 'Tap on cards above to select people to invite.'
                                  : '${_selectedUserIds.length} guest(s) will receive direct invitations.',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _selectedUserIds.isEmpty
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF047857),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // ── Who pays for the tickets ────────────────────────────────
                  // Only shown for a paid event; a free event has nothing to
                  // split and the whole section would be noise.
                  if (!_isFreeEvent) ...[
                    const Text(
                      'TICKET PAYMENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPrivacyCard(
                            title: 'I\'ll pay for both',
                            subtitle:
                                '2 × ${_money(_entryPrice)} = ${_money(_entryPrice * 2)}',
                            isSelected: _selectedPaymentType == 'self_pay',
                            onTap: () =>
                                setState(() => _selectedPaymentType = 'self_pay'),
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildPrivacyCard(
                            title: 'Split it',
                            subtitle:
                                'You ${_money(_entryPrice)} · They ${_money(_entryPrice)}',
                            isSelected: _selectedPaymentType == 'split',
                            onTap: () =>
                                setState(() => _selectedPaymentType = 'split'),
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'You pay now',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                _money(_hostPaysNow),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: LunaraTheme.electricViolet,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _selectedPaymentType == 'self_pay'
                                ? 'Both tickets are reserved as soon as your payment is confirmed.'
                                : 'Your ticket is reserved now. Your partner pays ${_money(_entryPrice)} when you accept their request.',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.celebration_rounded,
                              size: 18, color: Color(0xFF059669)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This event is free — both spots are reserved as soon as you post.',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                                color: Color(0xFF047857),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Post Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isPosting ? null : _submitPost,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _isPosting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'POST TO LIVE FEED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13.5,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Text('✨', style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillOption(String value, String label, bool isSelected, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? LunaraTheme.electricViolet
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? LunaraTheme.electricViolet : (isDark ? Colors.white12 : Colors.grey[300]!),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyCard({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? LunaraTheme.electricViolet.withValues(alpha: 0.1)
              : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? LunaraTheme.electricViolet : (isDark ? Colors.white12 : Colors.grey[300]!),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: isSelected ? LunaraTheme.electricViolet : Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? LunaraTheme.electricViolet : (isDark ? Colors.white : Colors.black),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteesSection(bool isDark) {
    if (_isLoadingInvitees) {
      return Container(
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey[200]!,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: LunaraTheme.electricViolet,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Finding available guests...',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_candidateInvitees.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey[200]!,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 32,
              color: isDark ? Colors.white38 : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              _inviteeSearchController.text.isNotEmpty
                  ? 'No matching users found for "${_inviteeSearchController.text}"'
                  : 'No available guests found right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Switch to "Public Feed" to let anyone request to join!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    final interestedList = _candidateInvitees.where((u) => u['isInterested'] == true).toList();
    final recommendedList = _candidateInvitees.where((u) => u['isInterested'] != true).toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          physics: const BouncingScrollPhysics(),
          children: [
            if (interestedList.isNotEmpty) ...[
              _buildSectionHeader('INTERESTED IN THIS NIGHT', isHighlight: true),
              const SizedBox(height: 6),
              ...interestedList.map((u) => _buildInviteeCard(u, isDark)),
              const SizedBox(height: 8),
            ],
            if (recommendedList.isNotEmpty) ...[
              _buildSectionHeader(
                interestedList.isNotEmpty ? 'RECOMMENDED GUESTS' : 'AVAILABLE GUESTS',
                isHighlight: false,
              ),
              const SizedBox(height: 6),
              ...recommendedList.map((u) => _buildInviteeCard(u, isDark)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {required bool isHighlight}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          if (isHighlight) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'HOT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: TextStyle(
              color: isHighlight ? const Color(0xFFFF5722) : const Color(0xFF64748B),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteeCard(Map<String, dynamic> user, bool isDark) {
    final userId = user['userId']?.toString() ?? user['id']?.toString() ?? '';
    final isSelected = _selectedUserIds.contains(userId);
    final name = user['firstName'] ?? user['name'] ?? 'User';
    final age = user['age'];
    final city = user['city'] ?? '';
    final photo = user['primaryPhoto'] ?? user['profilePhotoUrl'] ?? user['photoUrl'];
    final isVerified = user['isVerified'] == true;
    final isInterested = user['isInterested'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleUserSelection(userId),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? LunaraTheme.electricViolet.withValues(alpha: isDark ? 0.18 : 0.08)
                  : (isInterested
                      ? (isDark ? const Color(0xFF231E2A) : const Color(0xFFFFF7ED))
                      : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? LunaraTheme.electricViolet
                    : (isInterested
                        ? const Color(0xFFFFB74D).withValues(alpha: 0.4)
                        : (isDark ? Colors.white10 : const Color(0xFFE2E8F0))),
                width: isSelected ? 1.8 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    LunaraProfileImage(
                      userData: {'profilePhotoUrl': photo},
                      radius: 20,
                    ),
                    if (isVerified)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.verified,
                            color: LunaraTheme.cyberCyan,
                            size: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              age != null ? '$name, $age' : name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isInterested) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'INTERESTED 🔥',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (city.toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          city.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? LunaraTheme.electricViolet
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? LunaraTheme.electricViolet
                          : (isDark ? Colors.white38 : Colors.grey[400]!),
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
