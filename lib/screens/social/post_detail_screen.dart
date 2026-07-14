import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import 'package:lunara_app/screens/profile/profile_screen.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../discovery/venue_detail_screen.dart';
import '../../models/strangers_meet_request.dart';

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
  late Razorpay _razorpay;
  String? _lastOrderId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    if (widget.post['type'] == 'strangers_meet') {
      _loadStrangersMeetDetails();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _loadStrangersMeetDetails({bool showFullScreenLoader = true}) async {
    if (showFullScreenLoader) {
      setState(() => _isLoading = true);
    }
    final req = await ApiService.fetchStrangersMeetRequestById(widget.post['id']);
    if (mounted) {
      setState(() {
        _meetRequest = req;
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

  Future<void> _initiateJoinFlow() async {
    if (_meetRequest == null) return;
    setState(() => _isProcessing = true);

    // Call checkout / initiate endpoint on backend
    final checkoutData = await ApiService.initiateStrangersMeetJoinPayment(_meetRequest!.id);

    if (checkoutData == null) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to initiate join payment. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final double charges = _meetRequest!.chargesPerHead;

    if (charges > 0) {
      final String orderId = checkoutData['razorpayOrderId'];
      _lastOrderId = orderId;
      final String razorpayKeyId = checkoutData['razorpayKeyId'] ?? 'rzp_test_123';
      final int amount = checkoutData['amount'];

      var options = {
        'key': razorpayKeyId,
        'amount': amount,
        'name': 'Lunara',
        'description': 'Join Strangers Meet - ${_meetRequest!.subject}',
        'order_id': orderId,
        'prefill': {
          'contact': '8888888888',
          'email': 'test@razorpay.com'
        }
      };

      bool razorpayOpened = false;
      try {
        _razorpay.open(options);
        razorpayOpened = true;
      } catch (e) {
        debugPrint('Error opening Razorpay, falling back to simulated payment: $e');
      }

      if (!razorpayOpened) {
        // Fallback simulated payment
        Future.delayed(const Duration(seconds: 2), () {
          _confirmJoinPayment(orderId, 'mock_payment', 'mock_signature');
        });
      }
    } else {
      // Free join flow
      final String orderId = checkoutData['razorpayOrderId'] ?? 'free_order_${DateTime.now().millisecondsSinceEpoch}';
      _confirmJoinPayment(orderId, 'free', 'free');
    }
  }

  Future<void> _confirmJoinPayment(String orderId, String paymentId, String signature) async {
    if (_meetRequest == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ApiService.payStrangersMeetJoin(
      _meetRequest!.id,
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
      // Reload details to update slotsFilled and joiners list
      _loadStrangersMeetDetails();
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
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
                        value: foodPref,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.restaurant, color: LunaraTheme.electricViolet, size: 18),
                          prefixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        items: const ['Veg', 'Non-Veg', 'Both'].map((String val) {
                          return DropdownMenuItem<String>(
                            value: val,
                            child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
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
                        value: drinkPref,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.local_bar, color: LunaraTheme.electricViolet, size: 18),
                          prefixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        items: const ['Alcoholic', 'Non-Alcoholic', 'Both'].map((String val) {
                          return DropdownMenuItem<String>(
                            value: val,
                            child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          );
                        }).toList(),
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
                        Navigator.pop(ctx, {'food': foodPref, 'drink': drinkPref});
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

  Future<void> _sendJoinRequestWithPreferences(String foodPref, String drinkPref) async {
    if (_meetRequest == null) return;
    setState(() => _isProcessing = true);
    final success = await ApiService.sendStrangersMeetJoinRequest(
      _meetRequest!.id,
      foodPreference: foodPref,
      drinkPreference: drinkPref,
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request sent successfully! Waiting for host approval. 🤞'),
          backgroundColor: Colors.green,
        ),
      );
      _loadStrangersMeetDetails(showFullScreenLoader: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send join request. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
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
        content: const Text('Are you sure you want to mark this Strangers Meet as successfully completed? This action is permanent.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: LunaraTheme.electricViolet),
            child: const Text('COMPLETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
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
      return _buildStrangersMeetDetails();
    } else {
      return _buildPartyPlanDetails();
    }
  }

  // ─── Strangers Meet Details Layout ─────────────────────────────────────────
  Widget _buildStrangersMeetDetails() {
    final req = _meetRequest!;
    final String subject = req.subject;
    final String tagline = req.tagline;
    final double charges = req.chargesPerHead;
    final int slotsFilled = req.slotsFilled;
    final int maxPersons = req.numberOfPersons;
    final String venueName = req.venue?['name'] ?? 'Unknown Venue';

    final hostUserMap = req.user ?? {};
    final String hostFirstName = hostUserMap['firstName'] ?? 'Lunara';
    final String hostLastName = hostUserMap['lastName'] ?? 'User';
    final String? hostPhoto = hostUserMap['photoUrl'];

    final bool isMyPost = hostUserMap['id']?.toString() == ApiService.currentUserId;
    final String currentUserId = ApiService.currentUserId ?? '';

    Map<String, dynamic>? myJoinerInfo;
    if (req.joiners != null) {
      for (var j in req.joiners!) {
        if (j is Map && (j['userId']?.toString() == currentUserId || j['id']?.toString() == currentUserId)) {
          myJoinerInfo = Map<String, dynamic>.from(j);
          break;
        }
      }
    }

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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                              )
                            ]
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.whatshot, color: Colors.white, size: 12),
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: LunaraTheme.electricViolet,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'HAPPENING AT',
                                    style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    venueName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.venue != null)
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VenueDetailScreen(venue: widget.venue!),
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
                                    charges > 0 ? '₹${charges.toStringAsFixed(0)}' : 'FREE ENTRY',
                                    style: TextStyle(
                                      color: charges > 0 ? Colors.black : Colors.green,
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
                            backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                            backgroundImage: hostPhoto != null && hostPhoto.isNotEmpty
                                ? NetworkImage(hostPhoto.startsWith('http') ? hostPhoto : '${ApiService.baseUrl}$hostPhoto')
                                : null,
                            child: hostPhoto == null || hostPhoto.isEmpty
                                ? const Icon(Icons.person, color: LunaraTheme.electricViolet)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$hostFirstName $hostLastName',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                if (hostUserMap['bio'] != null && hostUserMap['bio'].toString().isNotEmpty)
                                  Text(
                                    hostUserMap['bio'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                  if (isMyPost) ...[
                    _buildPendingRequestsSection(),
                  ],

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
          child: _buildStrangersMeetActionButton(isMyPost, myJoinerInfo, slotsFilled, maxPersons, req.status, req.eventDateTime, charges),
        ),
      ),
    );
  }

  Widget _buildParticipantsSection() {
    final joiners = (_meetRequest?.joiners ?? []).where((j) {
      if (j is Map) {
        final status = j['status']?.toString();
        final payStatus = j['paymentStatus']?.toString();
        return status == 'accepted' || status == 'paid' || payStatus == 'paid';
      }
      return false;
    }).toList();
    if (joiners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Text(
          'PEOPLE JOINING',
          style: TextStyle(
            color: Colors.black38,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: joiners.length,
            itemBuilder: (context, index) {
              final joiner = joiners[index];
              final ju = joiner['user'] as Map<String, dynamic>?;
              if (ju == null) return const SizedBox.shrink();

              final name = ju['firstName'] ?? 'User';
              final photo = ju['photoUrl'];
              String? finalPhoto = photo;
              if (finalPhoto != null && finalPhoto.startsWith('/') && !finalPhoto.startsWith('assets')) {
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
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                        backgroundImage: finalPhoto != null && finalPhoto.isNotEmpty
                            ? NetworkImage(finalPhoto)
                            : null,
                        child: finalPhoto == null || finalPhoto.isEmpty
                            ? const Icon(Icons.person, color: LunaraTheme.electricViolet)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPendingRequestsSection() {
    final pendingJoiners = (_meetRequest?.joiners ?? []).where((j) {
      if (j is Map) {
        return j['status']?.toString() == 'pending';
      }
      return false;
    }).toList();

    if (pendingJoiners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Text(
          'PENDING REQUESTS TO JOIN',
          style: TextStyle(
            color: Colors.black38,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: pendingJoiners.length,
          itemBuilder: (context, index) {
            final joiner = pendingJoiners[index];
            final ju = joiner['user'] as Map<String, dynamic>?;
            if (ju == null) return const SizedBox.shrink();

            final name = '${ju['firstName'] ?? ''} ${ju['lastName'] ?? ''}'.trim();
            final photo = ju['photoUrl'];
            String? finalPhoto = photo;
            if (finalPhoto != null && finalPhoto.startsWith('/') && !finalPhoto.startsWith('assets')) {
              finalPhoto = '${ApiService.baseUrl}$finalPhoto';
            }

            final joinerId = joiner['id'].toString();

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: LunaraTheme.electricViolet.withOpacity(0.08),
                    backgroundImage: finalPhoto != null && finalPhoto.isNotEmpty
                        ? NetworkImage(finalPhoto)
                        : null,
                    child: finalPhoto == null || finalPhoto.isEmpty
                        ? const Icon(Icons.person, color: LunaraTheme.electricViolet)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'User' : name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (ju['phone'] != null && ju['phone'].toString().isNotEmpty)
                          Text(
                            ju['phone'].toString(),
                            style: TextStyle(color: Colors.grey[600], fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Reject button
                  IconButton(
                    onPressed: () => _handleRequest(joinerId, 'reject'),
                    icon: const Icon(Icons.close_rounded, color: Colors.red),
                    tooltip: 'Reject',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Accept button
                  IconButton(
                    onPressed: () => _handleRequest(joinerId, 'accept'),
                    icon: const Icon(Icons.check_rounded, color: Colors.green),
                    tooltip: 'Accept',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _handleRequest(String joinerId, String action) async {
    if (_meetRequest == null) return;
    setState(() => _isProcessing = true);
    final success = await ApiService.handleStrangersMeetJoinRequest(
      _meetRequest!.id,
      joinerId,
      action,
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'accept' ? 'Join request accepted!' : 'Join request rejected.'),
          backgroundColor: action == 'accept' ? Colors.green : Colors.grey[800],
        ),
      );
      _loadStrangersMeetDetails(showFullScreenLoader: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to handle join request. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

    final now = DateTime.now();
    final bool hasEnded = now.isAfter(eventDateTime);

    if (isMyPost) {
      if (hasEnded) {
        if (status == 'completed') {
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        // Event in future
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              'WAITING FOR MEET TIME TO END',
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
    } else {
      // Not host
      if (status == 'completed' || hasEnded) {
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
        final jStatus = myJoinerInfo['status']?.toString();
        final payStatus = myJoinerInfo['paymentStatus']?.toString();

        if (jStatus == 'paid' || payStatus == 'paid') {
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'JOINED',
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
        } else if (jStatus == 'pending') {
          return Container(
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
                  Icon(Icons.hourglass_empty_rounded, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'REQUEST PENDING APPROVAL',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: Colors.grey,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (jStatus == 'accepted') {
          final payText = charges > 0 ? 'PAY TO JOIN (₹${charges.toStringAsFixed(0)})' : 'CONFIRM JOIN (FREE)';
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00FF87), Color(0xFF60EFFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FF87).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _initiateJoinFlow,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.payment_rounded, color: Colors.black87),
                  const SizedBox(width: 12),
                  Text(
                    payText,
                    style: const TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (jStatus == 'rejected') {
          return Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_outlined, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'REQUEST REJECTED BY HOST',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: Colors.red,
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

      if (slotsFilled >= maxPersons) {
        return Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              'SLOTS FULL',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }

      // If user hasn't requested to join at all
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
        child: ElevatedButton(
          onPressed: _sendJoinRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                'REQUEST TO JOIN',
                style: TextStyle(
                  fontFamily: 'AllroundGothic',
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ─── Party Plan (Normal Post) Details Layout ───────────────────────────────
  Widget _buildPartyPlanDetails() {
    final String firstName = widget.post['firstName'] ?? 'Lunara';
    final String lastName = widget.post['lastName'] ?? 'User';
    final String venueName = widget.post['venue'] ?? 'Unknown Venue';

    final String content = widget.post['content'] ?? '';
    final String time = widget.post['time'] ?? '';

    final String? photo = widget.post['profilePhotoUrl'] ?? widget.post['profilePhoto'] ?? widget.post['image'];
    final bool isMyPost = widget.post['userId']?.toString() == ApiService.currentUserId ||
        (widget.post['user'] != null && widget.post['user']['id']?.toString() == ApiService.currentUserId);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, firstName, lastName, time, photo, widget.post),
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
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
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
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: LunaraTheme.electricViolet,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'HAPPENING AT',
                                    style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    venueName.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.venue != null)
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VenueDetailScreen(venue: widget.venue!),
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
                      ],
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
                child: Container(
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
                  child: ElevatedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final success = await ApiService.requestToJoinPartyPlan(
                        widget.post['id'],
                      );
                      if (success) {
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
                                  Icon(
                                    Icons.auto_awesome,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'YOUR REQUEST TO JOIN THE VIBE HAS BEEN SENT!',
                                      style: TextStyle(
                                        fontFamily: 'AllroundGothic',
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
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Failed to send request. You may have already requested.',
                            ),
                            backgroundColor: Colors.red,
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
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          'JOIN THE VIBE',
                          style: TextStyle(
                            fontFamily: 'AllroundGothic',
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
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
    String? finalPhoto = photo;
    if (finalPhoto != null &&
        finalPhoto.startsWith('/') &&
        !finalPhoto.startsWith('assets')) {
      finalPhoto = '${ApiService.baseUrl}$finalPhoto';
    }

    // Age
    int? age = post['age'] as int?;
    if (age == null) {
      final dobRaw = post['dateOfBirth'] ?? post['dob'];
      if (dobRaw != null) {
        final dob = DateTime.tryParse(dobRaw.toString());
        if (dob != null) {
          final today = DateTime.now();
          age = today.year - dob.year -
              ((today.month < dob.month || (today.month == dob.month && today.day < dob.day)) ? 1 : 0);
        }
      }
    }

    final bool isVerified = post['isVerified'] == true || post['verified'] == true;

    return SliverAppBar(
      expandedHeight: 450,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.black.withValues(alpha: 0.3),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      actions: [
        // Profile view button
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            child: IconButton(
              icon: const Icon(Icons.person, color: Colors.white),
              onPressed: () {
                User? profileUser;
                try {
                  profileUser = User.fromJson(post['user'] ?? post);
                } catch (e) {
                  // Fallback
                }
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
            if (finalPhoto != null && finalPhoto.isNotEmpty && finalPhoto.startsWith('http'))
              Image.network(
                finalPhoto,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  decoration: const BoxDecoration(
                    gradient: LunaraTheme.deepPurpleGradient,
                  ),
                ),
              )
            else if (finalPhoto != null && finalPhoto.isNotEmpty && finalPhoto.startsWith('assets'))
              Image.asset(finalPhoto, fit: BoxFit.cover)
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LunaraTheme.deepPurpleGradient,
                ),
              ),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 30,
              left: 24,
              right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '$firstName $lastName'.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            fontFamily: 'AllroundGothic',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (age != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          ', $age',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                      if (isVerified) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF2196F3),
                          size: 26,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          time,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
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
