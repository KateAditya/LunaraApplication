import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/subscription_provider.dart';
import '../../widgets/smart_checkout_sheet.dart';

enum VIPPaymentState {
  initial,
  paymentPending,
  paymentSuccess,
  paymentFailed,
  verificationPending,
  verificationFailed,
  subscriptionActive,
  subscriptionActivationFailed,
}

class VIPMembershipScreen extends StatefulWidget {
  const VIPMembershipScreen({super.key});

  @override
  State<VIPMembershipScreen> createState() => _VIPMembershipScreenState();
}

class _VIPMembershipScreenState extends State<VIPMembershipScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Razorpay _razorpay;

  bool _isLoading = true;
  bool _isProcessing = false;
  VIPPaymentState _paymentState = VIPPaymentState.initial;

  List<dynamic> _allPackages = [];

  String? get _activePackageId {
    final status = SubscriptionProvider.instance.status;
    return status.isActive ? status.packageId : null;
  }

  int get _activeRemainingDays {
    final status = SubscriptionProvider.instance.status;
    return status.isActive ? status.remainingDays : 0;
  }

  String? get _activePackageTier {
    final status = SubscriptionProvider.instance.status;
    return status.isActive ? status.tier : null;
  }

  int get _boostsRemaining {
    final status = SubscriptionProvider.instance.status;
    return status.boostsRemaining;
  }

  // Selected Options
  int _selectedPlanIndex = 0; // 0: Core, 1: Plus, 2: Pro, 3: Elite
  int _selectedEliteIndex = 0; // Index of selected Elite duration option
  int _selectedBoostOption =
      0; // 0: 1 Boost, 1: 2 Boosts, 2: 3 Boosts, 3: 5 Boosts

  final List<Map<String, dynamic>> _boostOptions = [
    {'count': 1, 'price': 49, 'label': '1 Boost'},
    {'count': 2, 'price': 90, 'label': '2 Boosts'},
    {'count': 3, 'price': 140, 'label': '3 Boosts'},
    {'count': 5, 'price': 160, 'label': '5 Boosts'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  List<dynamic> _userSubscriptions = [];

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final packages = await ApiService.fetchSubscriptionPackages();
      final currentSub = await ApiService.fetchUserSubscription();
      final plans = await ApiService.fetchUserSubscriptions();
      await ApiService.fetchProfile();

      setState(() {
        _allPackages = packages;
        _userSubscriptions = plans;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading VIP screen data: $e');
      setState(() => _isLoading = false);
    }
  }

  // Selected duration index map per tier index
  final Map<int, int> _selectedDurationIndexMap = {};

  // Get list of unique tiers in display order
  List<String> get _tiers {
    final Set<String> tiers = {};
    for (final p in _allPackages) {
      final tier = p['tier'] as String?;
      if (tier != null && tier != 'FREE') {
        tiers.add(tier);
      }
    }
    final List<String> sortedTiers = tiers.toList();
    const order = ['CORE', 'PLUS', 'PRO', 'ELITE'];
    sortedTiers.sort((a, b) {
      final idxA = order.indexOf(a);
      final idxB = order.indexOf(b);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return a.compareTo(b);
    });
    return sortedTiers;
  }

  List<dynamic> get _packagesForSelectedTier {
    final listTiers = _tiers;
    if (listTiers.isEmpty || _selectedPlanIndex >= listTiers.length) return [];
    final tier = listTiers[_selectedPlanIndex];
    final list = _allPackages.where((p) => p['tier'] == tier).toList();
    list.sort(
      (a, b) => (a['durationDays'] as num).compareTo(b['durationDays'] as num),
    );
    return list;
  }

  dynamic get _selectedPackage {
    final pkgs = _packagesForSelectedTier;
    if (pkgs.isEmpty) return null;
    int durationIndex = _selectedDurationIndexMap[_selectedPlanIndex] ?? 0;
    if (_selectedPlanIndex < _tiers.length &&
        _tiers[_selectedPlanIndex] == 'ELITE') {
      durationIndex = _selectedEliteIndex;
    }
    if (durationIndex >= pkgs.length) {
      durationIndex = 0;
    }
    return pkgs[durationIndex];
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) {
    debugPrint('[VIP] Razorpay payment success');
    debugPrint('[VIP] Payment ID received: ${response.paymentId}');
    debugPrint('[VIP] Order ID received: ${response.orderId}');
    debugPrint('[VIP] Signature received: ${response.signature != null}');

    setState(() {
      _paymentState = VIPPaymentState.paymentSuccess;
    });

    if (_tabController.index == 0) {
      // Package Purchase
      final pkg = _selectedPackage;
      if (pkg != null) {
        _confirmPackagePurchase(
          pkg['id'],
          response.orderId ??
              'order_mock_${DateTime.now().millisecondsSinceEpoch}',
          response.paymentId ??
              'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
          response.signature ?? 'mock_signature',
        );
      }
    } else {
      // Boost Purchase
      final boost = _boostOptions[_selectedBoostOption];
      _confirmBoostPurchase(
        boost['count'],
        response.orderId ??
            'order_mock_${DateTime.now().millisecondsSinceEpoch}',
        response.paymentId ??
            'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        response.signature ?? 'mock_signature',
      );
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    debugPrint('[VIP] Razorpay payment failed: ${response.message}');
    setState(() {
      _isProcessing = false;
      _paymentState = VIPPaymentState.paymentFailed;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() {
      _isProcessing = false;
      _paymentState = VIPPaymentState.paymentFailed;
    });
  }

  Future<void> _initiatePurchase() async {
    final pkg = _selectedPackage;
    if (pkg == null) return;

    final int currentRank = _getTierRank(_activePackageTier);
    final int selectedRank = _getTierRank(pkg['tier']);

    if (currentRank >= 0 && selectedRank <= currentRank) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have a higher or equal VIP plan active.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    debugPrint('[VIP] Selected plan: ${pkg['name']}');
    debugPrint('[VIP] Creating Razorpay order/subscription');

    setState(() {
      _isProcessing = true;
      _paymentState = VIPPaymentState.paymentPending;
    });

    // Call the backend to create a real Razorpay Order!
    final orderData = await ApiService.createSubscriptionOrder(pkg['id']);
    if (orderData == null) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to initiate subscription payment. Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String orderId = orderData['razorpayOrderId'];
    final int amount = orderData['amount'];
    final String keyId = orderData['keyId'] ?? 'rzp_test_123';

    var options = {
      'key': keyId,
      'amount': amount,
      'name': 'Lunara VIP',
      'description': 'Subscription - ${pkg['name']}',
      'order_id': orderId,
      'prefill': {'contact': '8888888888', 'email': 'vip@lunara.com'},
    };

    bool razorpayOpened = false;
    try {
      debugPrint('[VIP] Razorpay checkout opened');
      _razorpay.open(options);
      razorpayOpened = true;
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
    }

    if (!razorpayOpened) {
      // Simulate checkout callback in test/simulated environment
      Future.delayed(const Duration(seconds: 2), () {
        _confirmPackagePurchase(
          pkg['id'],
          orderId,
          'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
          'mock_signature',
        );
      });
    }
  }

  int _getTierRank(String? t) {
    if (t == null || t.isEmpty) return -1;
    const order = ['FREE', 'CORE', 'PLUS', 'PRO', 'ELITE', 'ELITE VIP'];
    final upperT = t.toUpperCase();
    for (int i = 0; i < order.length; i++) {
      if (upperT.contains(order[i])) return i;
    }
    return -1;
  }

  Future<void> _confirmPlanAction(
    String actionText,
    dynamic pkg,
    double price,
  ) async {
    SmartCheckoutSheet.show(
      context: context,
      title: 'Lunara VIP - ${pkg['name'] ?? pkg['tier']}',
      subtitle: '$actionText to ${pkg['tier']} Tier',
      itemPrice: price,
      onWalletPayment: () async {
        final res = await ApiService.payVipWithWallet(
          packageId: pkg['id'] ?? '',
          tier: pkg['tier'] ?? 'PRO',
          price: price,
        );
        if (res != null && res['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Successfully upgraded to ${pkg['name'] ?? pkg['tier']}! 🎉',
                ),
                backgroundColor: const Color(0xFF10B981),
              ),
            );
          }
          await SubscriptionProvider.instance.refreshAfterPurchase();
          await _loadData();
          return true;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res?['message'] ?? 'Wallet payment failed'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return false;
        }
      },
      onDirectPayment: () async {
        await _initiatePurchase();
      },
      onHybridPayment: (shortfallAmount) async {
        final orderData = await ApiService.createWalletRechargeOrder(
          shortfallAmount,
        );
        if (orderData != null) {
          final String orderId = orderData['orderId'] ?? orderData['id'] ?? '';
          final options = {
            'key': orderData['keyId'] ?? 'rzp_test_key',
            'amount': (shortfallAmount * 100).toInt(),
            'name': 'Lunara VIP Shortfall',
            'description':
                'Recharge ₹${shortfallAmount.toStringAsFixed(0)} for ${pkg['name'] ?? pkg['tier']}',
            'order_id': orderId,
            'theme': {'color': '#7F00FF'},
          };

          _razorpay.open(options);
        }
      },
    );
  }

  Future<void> _initiateBoostPurchase() async {
    final boost = _boostOptions[_selectedBoostOption];
    setState(() => _isProcessing = true);

    // Call the backend to create a real Razorpay Order!
    final orderData = await ApiService.createBoostOrder(boost['count']);
    if (orderData == null) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to initiate boost payment. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String orderId = orderData['razorpayOrderId'];
    final int amount = orderData['amount'];
    final String keyId = orderData['keyId'] ?? 'rzp_test_123';

    var options = {
      'key': keyId,
      'amount': amount,
      'name': 'Lunara Profile Boost',
      'description': 'Boost Pack - ${boost['label']}',
      'order_id': orderId,
      'prefill': {'contact': '8888888888', 'email': 'boost@lunara.com'},
    };

    bool razorpayOpened = false;
    try {
      _razorpay.open(options);
      razorpayOpened = true;
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
    }

    if (!razorpayOpened) {
      Future.delayed(const Duration(seconds: 2), () {
        _confirmBoostPurchase(
          boost['count'],
          orderId,
          'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
          'mock_signature',
        );
      });
    }
  }

  Future<void> _confirmPackagePurchase(
    String packageId,
    String orderId,
    String paymentId,
    String signature,
  ) async {
    debugPrint('[VIP] Calling payment verification API');
    setState(() {
      _paymentState = VIPPaymentState.verificationPending;
    });

    final response = await ApiService.purchaseSubscription(
      packageId: packageId,
      gatewayOrderId: orderId,
      gatewayPaymentId: paymentId,
      razorpaySignature: signature,
    );

    setState(() => _isProcessing = false);

    if (response['success'] == true) {
      debugPrint('[VIP] Subscription activation result: success');
      debugPrint('[VIP] Refreshing subscription');
      setState(() => _paymentState = VIPPaymentState.subscriptionActive);
      debugPrint('[VIP] Subscription ACTIVE');

      SubscriptionProvider.instance.refreshAfterPurchase();
      _showSuccessDialog(
        'Subscription Activated!',
        response['message'] ?? 'You have successfully upgraded your tier.',
      );
      _loadData();
    } else {
      debugPrint('[VIP] Payment verification failed');
      debugPrint('[VIP] HTTP status: ${response['statusCode']}');
      debugPrint('[VIP] Response: ${response['message']}');

      setState(
        () => _paymentState = VIPPaymentState.subscriptionActivationFailed,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment successful, but subscription activation is still processing.\nReason: ${response['message']}\nPlease wait a moment and refresh.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _confirmBoostPurchase(
    int boostCount,
    String orderId,
    String paymentId,
    String signature,
  ) async {
    debugPrint('[VIP] Calling boost payment verification API');
    setState(() {
      _paymentState = VIPPaymentState.verificationPending;
    });

    final response = await ApiService.purchaseBoost(
      boostCount: boostCount,
      gatewayOrderId: orderId,
      gatewayPaymentId: paymentId,
      razorpaySignature: signature,
    );

    setState(() => _isProcessing = false);

    if (response['success'] == true) {
      debugPrint('[VIP] Boost activation result: success');
      setState(() => _paymentState = VIPPaymentState.subscriptionActive);

      SubscriptionProvider.instance.refreshAfterPurchase();
      _showSuccessDialog(
        'Boosts Credited!',
        '${response['message'] ?? '$boostCount profile boosts have been added to your account.'}',
      );
      _loadData();
    } else {
      debugPrint('[VIP] Boost verification failed');
      setState(
        () => _paymentState = VIPPaymentState.subscriptionActivationFailed,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment successful, but boost activation is still processing.\nReason: ${response['message']}\nPlease wait a moment and refresh.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _useActiveBoost() async {
    setState(() => _isProcessing = true);
    try {
      final result = await ApiService.useBoost();
      setState(() => _isProcessing = false);
      if (result != null && result['success'] == true) {
        SubscriptionProvider.instance.refreshAfterPurchase();
        _showSuccessDialog(
          'Profile Boosted! ⚡',
          'Your profile is now boosted for the next 30 minutes! Get ready for more matches and views.',
        );
        _loadData();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to activate boost. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccessDialog(String title, String subtitle) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF16161E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'GREAT',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'LUNARA VIP',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: 1,
            ),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: LunaraTheme.electricViolet,
            indicatorWeight: 3,
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.38),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: 'VIP PASSES'),
              Tab(text: 'PROFILE BOOST'),
              Tab(text: 'PURCHASED PLANS'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: LunaraTheme.electricViolet,
                ),
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildVIPPassesTab(),
                  _buildProfileBoostTab(),
                  _buildPurchasedPlansTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildVIPPassesTab() {
    final pkg = _selectedPackage;
    if (pkg == null) {
      return Center(
        child: Text(
          'No subscription plans available.',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final double price = double.tryParse(pkg['price'].toString()) ?? 0.0;
    final String tier = pkg['tier'];
    final bool isActive = _activePackageId == pkg['id'];

    final int currentRank = _getTierRank(_activePackageTier);
    final int selectedRank = _getTierRank(tier);

    String actionText = 'GET PLAN';
    bool canPurchase = true;

    if (currentRank >= 0) {
      if (selectedRank > currentRank) {
        actionText = 'UPGRADE';
      } else if (selectedRank == currentRank) {
        actionText = 'EXTEND PLAN';
      } else {
        actionText = 'DOWNGRADE (FUTURE)';
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Selector Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_tiers.length, (index) {
                final tierName = _tiers[index];
                String label = tierName;
                if (tierName == 'CORE') label = 'Core';
                if (tierName == 'PLUS') label = 'Plus';
                if (tierName == 'PRO') label = 'Pro';
                if (tierName == 'ELITE') label = 'Elite VIP';

                final firstPkg = _allPackages.firstWhere(
                  (p) => p['tier'] == tierName,
                  orElse: () => null,
                );
                final color = _getPlanThemeColor(firstPkg);
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: _buildPlanPill(index, label, color),
                );
              }),
            ),
          ),
          const SizedBox(height: 24),

          // Plan Badge Card
          _buildPremiumCard(pkg),
          const SizedBox(height: 24),

          // Durations Selector (if selected tier has multiple options)
          if (_packagesForSelectedTier.length > 1) ...[
            Text(
              'SELECT PLAN DURATION',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            _buildDurationsSelector(),
            const SizedBox(height: 24),
          ],

          // Dynamic Feature List
          _buildDynamicFeatures(pkg),
          const SizedBox(height: 32),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isProcessing || !canPurchase
                  ? null
                  : () => _confirmPlanAction(actionText, pkg, price),
              style: ElevatedButton.styleFrom(
                backgroundColor: !canPurchase || isActive
                    ? Colors.grey[800]
                    : _getPlanThemeColor(pkg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      !canPurchase
                          ? actionText
                          : '$actionText FOR ₹${price.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: tier == 'ELITE' && canPurchase
                            ? Colors.black
                            : Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 32),

          // Purchase History Section
          _buildPurchaseHistory(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPurchaseHistory() {
    if (_subscriptionHistory.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PURCHASED VIP PLANS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        ..._subscriptionHistory.map((historyItem) {
          final pkg = historyItem['package'] ?? {};
          final status = historyItem['status'] ?? 'UNKNOWN';
          final tier = pkg['tier'] ?? 'UNKNOWN';
          final planName = pkg['name'] ?? tier;

          Color statusColor = Colors.grey;
          if (status == 'ACTIVE') statusColor = Colors.green;
          if (status == 'UPCOMING') statusColor = Colors.amber;

          final startDateStr = historyItem['startDate'] ?? '';
          final endDateStr = historyItem['endDate'] ?? '';

          String formatSimpleDate(String d) {
            if (d.isEmpty) return '';
            try {
              final dt = DateTime.parse(d).toLocal();
              return '${dt.day}-${dt.month}-${dt.year}';
            } catch (e) {
              return d;
            }
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E28) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      planName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Start: ${formatSimpleDate(startDateStr)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  'Expiry: ${formatSimpleDate(endDateStr)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildProfileBoostTab() {
    final selectedBoost = _boostOptions[_selectedBoostOption];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveBoosts =
        _boostsRemaining > 0 || _activePackageTier == 'ELITE';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Boost Intro Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple[900]!, Colors.purple[700]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BOOST YOUR VISIBILITY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Get up to 10x more likes, views, and responses! Your profile goes straight to the top of discovery in your area.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Icon(Icons.bolt, color: Colors.amber, size: 64),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Active Boost Credit Section
          if (hasActiveBoosts) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF2E1A47), const Color(0xFF140D24)]
                      : [Colors.purple.shade50, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.purple.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withValues(alpha: isDark ? 0.3 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTIVE BOOST CREDITS',
                            style: TextStyle(
                              color: Colors.purpleAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _activePackageTier == 'ELITE'
                                ? 'UNLIMITED BOOSTS'
                                : '$_boostsRemaining BOOSTS AVAILABLE',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.rocket_launch_rounded,
                          color: Colors.purpleAccent,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _useActiveBoost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: Colors.purple.withValues(alpha: 0.5),
                      ),
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bolt, color: Colors.amber),
                                SizedBox(width: 8),
                                Text(
                                  'ACTIVATE BOOST NOW',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],

          Text(
            'SELECT BOOST PACKAGE',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),

          // Boost Selection Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: _boostOptions.length,
            itemBuilder: (context, index) {
              final option = _boostOptions[index];
              final isSelected = _selectedBoostOption == index;
              final gridItemBg = isSelected
                  ? Colors.purple.withValues(alpha: 0.15)
                  : (isDark
                        ? const Color(0xFF16161E)
                        : const Color(0xFFF2F2F7));
              final gridItemBorder = isSelected
                  ? Colors.purple
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05));
              final labelColor = isDark ? Colors.white : Colors.black87;
              final priceColor = isSelected
                  ? Colors.purpleAccent
                  : (isDark ? Colors.white70 : Colors.black54);

              return GestureDetector(
                onTap: () => setState(() => _selectedBoostOption = index),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: gridItemBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: gridItemBorder, width: 2),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          option['label'],
                          style: TextStyle(
                            color: labelColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '₹${option['price']}',
                          style: TextStyle(
                            color: priceColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 40),

          // Boost Benefits Checklist
          _buildBoostChecklist(),
          const SizedBox(height: 40),

          // Boost Action Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _initiateBoostPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      'PURCHASE FOR ₹${selectedBoost['price']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanPill(int index, String label, Color color) {
    final isSelected = _selectedPlanIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillBgColor = isSelected
        ? color.withValues(alpha: 0.15)
        : (isDark ? const Color(0xFF16161E) : const Color(0xFFF2F2F7));
    final pillBorderColor = isSelected
        ? color
        : (isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05));
    final pillTextColor = isSelected
        ? color
        : (isDark ? Colors.white60 : Colors.black54);

    return GestureDetector(
      onTap: () => setState(() {
        _selectedPlanIndex = index;
        if (index < _tiers.length && _tiers[index] == 'ELITE') {
          _selectedEliteIndex = 0;
        }
        if (!_selectedDurationIndexMap.containsKey(index)) {
          _selectedDurationIndexMap[index] = 0;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: pillBgColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: pillBorderColor, width: 1.5),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: pillTextColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumCard(dynamic pkg) {
    final Color color = _getPlanThemeColor(pkg);
    final String name = pkg['name'];
    final double price = double.tryParse(pkg['price'].toString()) ?? 0.0;
    final int duration = pkg['durationDays'] ?? 0;
    final bool isActive = _activePackageId == pkg['id'];

    final String? badgeText =
        pkg['badge'] ??
        (pkg['is_popular'] == true
            ? 'POPULAR'
            : (pkg['is_recommended'] == true ? 'RECOMMENDED' : null));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = isDark ? const Color(0xFF16161E) : Colors.white;
    final textOnCardColor = isDark ? Colors.white : Colors.black;
    final subTextOnCardColor = isDark ? Colors.white38 : Colors.black38;
    final descOnCardColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.15), cardBgColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
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
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (badgeText != null && badgeText.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color),
                        ),
                        child: Text(
                          badgeText.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Text(
                          'ACTIVE • $_activeRemainingDays DAYS',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${price.toStringAsFixed(0)}',
                style: TextStyle(
                  color: textOnCardColor,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '/ $duration DAYS',
                style: TextStyle(
                  color: subTextOnCardColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _getPlanDescription(pkg),
            style: TextStyle(color: descOnCardColor, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationsSelector() {
    final pkgs = _packagesForSelectedTier;
    if (pkgs.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemBgColor = isDark
        ? const Color(0xFF16161E)
        : const Color(0xFFF2F2F7);
    final borderUnselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);

    final color = _getPlanThemeColor(_selectedPackage);

    return Row(
      children: List.generate(pkgs.length, (index) {
        final item = pkgs[index];
        final currentSelectedIdx =
            _selectedDurationIndexMap[_selectedPlanIndex] ?? 0;
        final isSelected = currentSelectedIdx == index;
        final int days = item['durationDays'] ?? 0;
        final double price = double.tryParse(item['price'].toString()) ?? 0.0;

        String label = '${days}d';
        if (days == 7) label = '7d';
        if (days == 14) label = '14d';
        if (days == 15) label = '15d';
        if (days == 30) label = '30d';
        if (days == 90) label = '3m';
        if (days == 180) label = '6m';
        if (days == 365) label = '12m';

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedDurationIndexMap[_selectedPlanIndex] = index;
              if (_tiers[_selectedPlanIndex] == 'ELITE') {
                _selectedEliteIndex = index;
              }
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.15) : itemBgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? color : borderUnselectedColor,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: isSelected
                          ? color
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${price.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : (isDark ? Colors.white38 : Colors.black38),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDynamicFeatures(dynamic pkg) {
    final String tier = pkg['tier'] ?? '';
    final Color color = _getPlanThemeColor(pkg);

    // List out benefits based on features in the pkg
    List<Map<String, String>> benefits = [];

    final featuresMap = pkg['features'] as Map<String, dynamic>?;
    if (featuresMap != null && featuresMap.isNotEmpty) {
      final sortedKeys = featuresMap.keys.toList();
      for (final key in sortedKeys) {
        final val = featuresMap[key];
        if (val is Map && val['enabled'] == true) {
          final String name = val['name'] ?? key;
          String desc = val['description'] ?? '';
          if (desc.isEmpty) {
            if (key == 'daily_likes') {
              final limit = val['value'] ?? 'unlimited';
              desc = 'Send up to $limit likes per day';
            } else if (key == 'daily_match_requests') {
              final limit = val['value'] ?? 'unlimited';
              desc = 'Send up to $limit match requests per day';
            } else if (key == 'daily_posts') {
              final limit = val['value'] ?? 'unlimited';
              desc = 'Create up to $limit posts per day';
            } else if (key == 'super_likes') {
              final limit = val['value'] ?? 0;
              desc = 'Includes $limit super likes per cycle';
            } else if (key == 'boosts') {
              final limit = val['value'] ?? 0;
              desc = 'Includes $limit profile boosts per cycle';
            } else if (key == 'hide_profile') {
              desc = 'Browse matches silently and anonymously';
            } else if (key == 'priority_visibility') {
              desc = 'Appear in front of users before non-premium users';
            } else if (key == 'trust_badge') {
              desc = 'Adds a premium verify check on your profile';
            } else if (key == 'elite_badge') {
              desc = 'Exclusive elite member badge layout';
            } else if (key == 'who_liked_me') {
              desc = 'Unmask interested users instantly';
            } else if (key == 'who_viewed_me') {
              desc = 'See who viewed your profile';
            }
          }
          benefits.add({'title': name, 'desc': desc});
        }
      }
    }

    // Backwards compatibility fallback if no features mapped
    if (benefits.isEmpty) {
      if (tier == 'CORE' ||
          tier == 'PLUS' ||
          tier == 'PRO' ||
          tier == 'ELITE') {
        benefits.addAll([
          {
            'title': 'Send Unlimited Match Requests',
            'desc': 'No daily swipe restrictions',
          },
          {
            'title': 'Unlimited Posts & Likes',
            'desc': 'Share and engage with no limits',
          },
          {
            'title': 'Who Liked/Viewed Your Profile',
            'desc': 'Unmask interested users instantly',
          },
        ]);
      }
      if (tier == 'PLUS' || tier == 'PRO' || tier == 'ELITE') {
        benefits.addAll([
          {
            'title': '10 Superlikes Per Cycle',
            'desc': 'Stand out in their notifications',
          },
          {
            'title': '2 Free Profile Boosts',
            'desc': 'Automatic ranking push in searches',
          },
          {
            'title': 'Hide Profile Mode',
            'desc': 'Browse matches silently and anonymously',
          },
        ]);
      }
      if (tier == 'PRO' || tier == 'ELITE') {
        benefits.addAll([
          {
            'title': 'Priority Visibility',
            'desc': 'Appear in front of users before non-Pro users',
          },
          {
            'title': '4 Free Profile Boosts',
            'desc': 'Enhanced package cycle boosts',
          },
          {
            'title': 'Trust Badge',
            'desc': 'Adds a premium verify check on your profile',
          },
        ]);
      }
      if (tier == 'ELITE') {
        benefits.addAll([
          {
            'title': 'Maximum Profile Boost',
            'desc': 'Stay at the very top of search feeds',
          },
          {
            'title': 'Elite User Badge',
            'desc': 'Exclusive premium badge layout',
          },
          {
            'title': 'Early Access to Pro Features',
            'desc': 'Test and access new updates first',
          },
        ]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INCLUDED BENEFITS',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 16),
        ...benefits.map((b) => _benefitItem(b['title']!, b['desc']!, color)),
      ],
    );
  }

  Widget _benefitItem(String title, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, color: color, size: 14),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoostChecklist() {
    return Column(
      children: [
        _boostChecklistItem('Appears at top based on city and location'),
        _boostChecklistItem('Higher visibility for your active party plans'),
        _boostChecklistItem('Gold-ring highlighted profile border'),
        _boostChecklistItem('Guaranteed increase in match requests & views'),
      ],
    );
  }

  Widget _boostChecklistItem(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.purpleAccent,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? const Color(0xCCFFFFFF) : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchasedPlansTab() {
    if (_userSubscriptions.isEmpty) {
      return Center(
        child: Text(
          'No purchased plans found.',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: LunaraTheme.electricViolet,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _userSubscriptions.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final sub = _userSubscriptions[index];
          final pkg = sub['package'];
          final status = sub['status'] ?? 'UNKNOWN';
          final startDate = DateTime.tryParse(sub['startDate'] ?? '');
          final endDate = DateTime.tryParse(sub['endDate'] ?? '');
          final purchaseDate = DateTime.tryParse(sub['createdAt'] ?? '');

          final String planName = pkg != null
              ? (pkg['name'] ?? 'VIP Plan')
              : 'Unknown Plan';
          final int duration = pkg != null ? (pkg['durationDays'] ?? 0) : 0;

          Color statusColor = Colors.grey;
          if (status == 'ACTIVE') {
            statusColor = Colors.green;
          } else if (status == 'UPCOMING')
            statusColor = Colors.orange;

          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF16161E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$planName ($duration Days)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDateRow('Purchase Date', purchaseDate),
                const SizedBox(height: 8),
                _buildDateRow('Start Date', startDate),
                const SizedBox(height: 8),
                _buildDateRow('Expiry Date', endDate),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateRow(String label, DateTime? date) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        Text(
          date != null ? '${date.day}-${date.month}-${date.year}' : 'N/A',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getPlanThemeColor(dynamic pkg) {
    if (pkg == null) return const Color(0xFF7F00FF);
    final String? themeStr = pkg['theme_color'] ?? pkg['themeColor'];
    if (themeStr != null && themeStr.startsWith('#')) {
      try {
        final hex = themeStr.replaceFirst('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    final String tier = pkg['tier'] ?? '';
    if (tier == 'CORE') return const Color(0xFF00A9FF);
    if (tier == 'PLUS') return const Color(0xFF7F00FF);
    if (tier == 'PRO') return const Color(0xFFE100FF);
    if (tier == 'ELITE') return const Color(0xFFFFB703);
    return const Color(0xFF7F00FF);
  }

  String _getPlanDescription(dynamic pkg) {
    if (pkg == null) return '';
    final String? desc = pkg['description'];
    if (desc != null && desc.isNotEmpty) return desc;

    final String tier = pkg['tier'] ?? '';
    if (tier == 'CORE') {
      return 'Perfect for daily swiping and standard messaging.';
    }
    if (tier == 'PLUS') return 'Boost your reach and browse anonymously.';
    if (tier == 'PRO') {
      return 'Stand out from the crowd with priority visibility.';
    }
    if (tier == 'ELITE') {
      return 'Maximum features, priority entry, and elite badges.';
    }
    return '';
  }
}
