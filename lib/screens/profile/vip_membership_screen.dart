import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/subscription_provider.dart';
import '../../models/vip_entitlement_model.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/top_notification_banner.dart';
import 'plan_usage_screen.dart';

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
  final int initialTabIndex;
  const VIPMembershipScreen({super.key, this.initialTabIndex = 0});

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

  // Add-ons state
  List<SubscriptionAddonPackageModel> _availableAddons = [];
  bool _isLoadingAddons = false;
  String? _pendingAddonPackageId; // tracks which addon is being purchased via Razorpay

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

  // Selected Options
  int _selectedPlanIndex = 0; // 0: Core, 1: Plus, 2: Pro, 3: Elite
  int _selectedEliteIndex = 0; // Index of selected Elite duration option

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex.clamp(0, 3));

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

    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (!kIsWeb) {
      try {
        _razorpay.clear();
      } catch (e) {
        debugPrint('Razorpay clear error: $e');
      }
    }
    super.dispose();
  }

  List<dynamic> _userSubscriptions = [];

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.fetchSubscriptionPackages(),
        ApiService.fetchUserSubscriptions(),
        ApiService.fetchProfile(),
      ]);

      if (mounted) {
        setState(() {
          _allPackages = (results[0] as List<dynamic>?) ?? [];
          _userSubscriptions = (results[1] as List<dynamic>?) ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading VIP screen data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
    // Load add-ons and entitlements in parallel (non-blocking)
    _loadAddons();
    SubscriptionProvider.instance.fetchEntitlementsSummary();
  }

  Future<void> _loadAddons() async {
    if (_isLoadingAddons) return;
    setState(() => _isLoadingAddons = true);
    try {
      await SubscriptionProvider.instance.fetchAvailableAddons();
      if (mounted) {
        setState(() {
          _availableAddons = SubscriptionProvider.instance.availableAddons;
          _isLoadingAddons = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading addons: $e');
      if (mounted) setState(() => _isLoadingAddons = false);
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
    debugPrint('[VIP] State updated: $_paymentState');

    if (_pendingAddonPackageId != null) {
      // Add-on Purchase via Razorpay (Add-ons tab or hybrid topup from any tab)
      _confirmAddonPurchase(
        _pendingAddonPackageId!,
        response.orderId ?? 'order_mock_${DateTime.now().millisecondsSinceEpoch}',
        response.paymentId ?? 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
        response.signature ?? 'mock_signature',
      );
    } else {
      // Package Purchase (VIP Pass)
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
    final success = await SmartCheckoutSheet.show(
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
            'theme': {'color': '#7C3AED'},
          };

          _razorpay.open(options);
        }
      },
    );

    if (success == true && mounted) {
      await SubscriptionProvider.instance.refreshAfterPurchase();
      await _loadData();
      _showSuccessDialog(
        'Subscription Activated! 🎉',
        'You have successfully upgraded to ${pkg['name'] ?? pkg['tier']}.',
        itemName: pkg['name'] ?? pkg['tier'],
        icon: Icons.workspace_premium_rounded,
        iconColor: const Color(0xFF7C3AED),
      );
    }
  }


  Future<void> _confirmPackagePurchase(
    String packageId,
    String orderId,
    String paymentId,
    String signature,
  ) async {
    debugPrint('[VIP] Calling payment verification API');
    setState(() => _isProcessing = true);

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


  Future<void> _launchRazorpayForAddon(SubscriptionAddonPackageModel addon) async {
    setState(() {
      _isProcessing = true;
      _pendingAddonPackageId = addon.id;
    });
    final orderData = await ApiService.createAddonRazorpayOrder(addon.id);
    if (orderData == null) {
      setState(() { _isProcessing = false; _pendingAddonPackageId = null; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create order. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final options = {
      'key': orderData['keyId'] ?? orderData['razorpayKeyId'] ?? 'rzp_test_key',
      'amount': orderData['amount'] ?? (addon.price * 100).toInt(),
      'name': 'Lunara Add-on',
      'description': addon.name,
      'order_id': orderData['orderId'] ?? orderData['razorpayOrderId'] ?? '',
      'prefill': {'contact': '9999999999', 'email': 'user@lunara.app'},
      'theme': {'color': '#7C3AED'},
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      setState(() { _isProcessing = false; _pendingAddonPackageId = null; });
      debugPrint('Error opening Razorpay for addon: $e');
    }
  }

  Future<void> _confirmAddonPurchase(
    String addonPackageId,
    String orderId,
    String paymentId,
    String signature,
  ) async {
    setState(() => _isProcessing = true);
    final response = await ApiService.verifyAddonRazorpayPayment(
      addonPackageId: addonPackageId,
      razorpayOrderId: orderId,
      razorpayPaymentId: paymentId,
      razorpaySignature: signature,
    );
    setState(() {
      _isProcessing = false;
      _pendingAddonPackageId = null;
    });
    if (response['success'] == true) {
      await SubscriptionProvider.instance.refreshAfterPurchase();
      await _loadAddons();
      await _loadData();
      if (mounted) {
        SubscriptionAddonPackageModel? purchasedAddon;
        for (final a in _availableAddons) {
          if (a.id == addonPackageId) {
            purchasedAddon = a;
            break;
          }
        }
        final featKey = purchasedAddon?.featureKey ?? response['featureKey'] ?? 'addon';
        final name = purchasedAddon?.name ?? response['addonName'] ?? 'Add-on Pack';
        final newBal = _currentBalance(featKey);
        final unit = _addonUnit(featKey);

        TopNotificationBanner.show(
          title: 'Purchase Successful! 🎉',
          body: response['message'] ?? '$name has been credited to your account.',
          iconData: _addonIcon(featKey),
        );

        _showSuccessDialog(
          'Purchase Successful! 🎉',
          response['message'] ?? '$name has been credited to your account.',
          itemName: name,
          balanceInfo: '$newBal $unit',
          icon: _addonIcon(featKey),
          iconColor: _addonColor(featKey),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'Add-on activation still processing. Please refresh.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _showSuccessDialog(
    String title,
    String subtitle, {
    String? itemName,
    String? balanceInfo,
    IconData? icon,
    Color? iconColor,
  }) {
    final brandColor = iconColor ?? const Color(0xFF10B981);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF16161E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      brandColor.withValues(alpha: 0.25),
                      brandColor.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: brandColor.withValues(alpha: 0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: brandColor.withValues(alpha: 0.35),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    icon ?? Icons.check_rounded,
                    color: brandColor,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              if (itemName != null || balanceInfo != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    children: [
                      if (itemName != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Item', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(itemName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                      if (itemName != null && balanceInfo != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                        ),
                      if (balanceInfo != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Updated Balance', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            Text(balanceInfo, style: TextStyle(color: brandColor, fontSize: 13, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'AWESOME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
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
            tabAlignment: TabAlignment.start,
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
              Tab(text: 'ADD-ONS'),
              Tab(text: 'USAGE & QUOTA'),
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
                  _buildAddonsTab(),
                  PlanUsageContent(
                    onGoToVIPPasses: () => _tabController.animateTo(0),
                    onGoToAddons: () => _tabController.animateTo(1),
                  ),
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
                      '$actionText FOR ₹${price.toStringAsFixed(0)}',
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
    if (_userSubscriptions.isEmpty) return const SizedBox.shrink();

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
        ..._userSubscriptions.map((historyItem) {
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
    final String tier = (pkg['tier'] ?? '').toString().toUpperCase();
    final Color color = _getPlanThemeColor(pkg);

    final dailyLikesLimit = pkg['dailyLikesLimit'] ?? pkg['daily_likes_limit'];
    final dailyBacktracks = pkg['backtrackLimit'] ?? pkg['backtrack_limit'] ?? pkg['daily_backtracks_limit'];
    final superlikes = pkg['superlikesPerCycle'] ?? pkg['super_likes_per_cycle'] ?? pkg['superlikes'];
    final boosts = pkg['boostsPerCycle'] ?? pkg['boosts_per_cycle'] ?? pkg['boosts'];
    final partyPlans = pkg['partyPlanLimit'] ?? pkg['party_plan_limit'];
    final matchRequests = pkg['dailyMatchRequestsLimit'] ?? pkg['daily_match_requests_limit'];
    final dailyPosts = pkg['dailyPostsLimit'] ?? pkg['daily_posts_limit'];

    List<Map<String, String>> benefits = [];

    // Parse features map if available from backend
    final featuresMap = pkg['features'] as Map<String, dynamic>?;
    if (featuresMap != null && featuresMap.isNotEmpty) {
      for (final entry in featuresMap.entries) {
        final key = entry.key;
        final val = entry.value;
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
            } else if (key == 'daily_backtracks' || key == 'backtracks') {
              final limit = val['value'] ?? 'unlimited';
              desc = '$limit backtracks/day to undo accidental swipes';
            } else if (key == 'party_plans') {
              final limit = val['value'] ?? 'unlimited';
              desc = 'Create up to $limit active party plans';
            } else if (key == 'hide_profile') {
              desc = 'Browse matches silently and anonymously';
            } else if (key == 'priority_visibility') {
              desc = 'Appear in front of users before non-premium users';
            } else if (key == 'trust_badge') {
              desc = 'Adds a premium verified check on your profile';
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

    // Comprehensive Fallback/Augmentation: Ensure all key benefits and quotas are fully shown
    if (benefits.isEmpty) {
      if (tier == 'CORE') {
        final likesText = dailyLikesLimit != null ? '$dailyLikesLimit Likes per day' : '50 Likes per day';
        final backtrackText = dailyBacktracks != null ? '$dailyBacktracks Backtracks per day' : '5 Backtracks per day';
        final requestsText = matchRequests != null ? '$matchRequests Match requests per day' : '30 Requests per day';
        final postsText = dailyPosts != null ? '$dailyPosts Party/Social posts per day' : '5 Posts per day';

        benefits.addAll([
          {
            'title': 'Daily Likes & Swipes',
            'desc': '$likesText to connect with matches',
          },
          {
            'title': 'Backtrack Last Swipe',
            'desc': '$backtrackText — undo accidental left swipes',
          },
          {
            'title': 'Send Match Requests',
            'desc': '$requestsText with personalized intro messages',
          },
          {
            'title': 'Party Plans & Event Posts',
            'desc': '$postsText to invite friends and match partners',
          },
          {
            'title': 'Who Liked & Viewed You',
            'desc': 'Unmask interested profiles & view visitor history',
          },
          {
            'title': 'Ad-Free Experience',
            'desc': 'Browse and chat seamlessly without distractions',
          },
        ]);
      } else if (tier == 'PLUS') {
        final backtrackText = dailyBacktracks != null ? '$dailyBacktracks Backtracks/day' : '10 Backtracks/day';
        final superlikesText = superlikes != null ? '$superlikes Superlikes per cycle' : '10 Superlikes per cycle';
        final boostsText = boosts != null ? '$boosts Profile Boosts included' : '2 Free Profile Boosts included';
        final requestsText = matchRequests != null ? '$matchRequests Match requests per day' : '50 Requests per day';

        benefits.addAll([
          {
            'title': 'Unlimited Likes & Swipes',
            'desc': 'No daily swipe restrictions or cooldown timer',
          },
          {
            'title': 'Backtrack Last Swipe',
            'desc': '$backtrackText — rewind and change your decision',
          },
          {
            'title': 'Superlikes Included',
            'desc': '$superlikesText to stand out directly in their inbox',
          },
          {
            'title': 'Profile Boosts',
            'desc': '$boostsText — climb straight to the top of discovery',
          },
          {
            'title': 'Send Match Requests',
            'desc': '$requestsText with priority delivery',
          },
          {
            'title': 'Who Liked / Viewed My Profile',
            'desc': 'Instant unmasking of interested profiles and visitors',
          },
          {
            'title': 'Hide Profile Mode (Stealth)',
            'desc': 'Browse matches silently and anonymously',
          },
          {
            'title': 'Expanded Party Plans & Posts',
            'desc': 'Create and publish multiple active party plans',
          },
        ]);
      } else if (tier == 'PRO') {
        final backtrackText = dailyBacktracks != null ? '$dailyBacktracks Backtracks/day' : '15 Backtracks/day';
        final superlikesText = superlikes != null ? '$superlikes Superlikes per cycle' : '25 Superlikes per cycle';
        final boostsText = boosts != null ? '$boosts Profile Boosts included' : '4 Free Profile Boosts included';
        final partyPlanText = partyPlans != null ? 'Create up to $partyPlans active party plans' : 'Create & host multiple featured party plans';

        benefits.addAll([
          {
            'title': 'Unlimited Likes & Swipes',
            'desc': 'Infinite swipe deck with zero limits or delays',
          },
          {
            'title': 'Backtrack Last Swipe',
            'desc': '$backtrackText — effortless undo on any swipe',
          },
          {
            'title': 'Generous Superlikes Pack',
            'desc': '$superlikesText with 3x higher match rate',
          },
          {
            'title': 'Monthly Profile Boosts',
            'desc': '$boostsText for 10x profile visibility',
          },
          {
            'title': 'Priority Match Visibility',
            'desc': 'Appear in front of users before standard & free members',
          },
          {
            'title': 'Party Plans & Event Creation',
            'desc': partyPlanText,
          },
          {
            'title': 'Trust Badge on Profile',
            'desc': 'Verified VIP checkmark next to your name',
          },
          {
            'title': 'Who Liked / Viewed Me',
            'desc': 'Full access to incoming likes, match requests & profile viewers',
          },
          {
            'title': 'Incognito Stealth Browsing',
            'desc': 'Browse and interact with complete privacy controls',
          },
        ]);
      } else if (tier == 'ELITE') {
        final superlikesText = superlikes != null ? '$superlikes Superlikes per cycle' : '50 Superlikes per cycle';
        final boostsText = (boosts != null && boosts > 10) ? 'Unlimited Profile Boosts' : 'Unlimited / 10+ Profile Boosts';

        benefits.addAll([
          {
            'title': 'Unlimited Likes, Swipes & Requests',
            'desc': 'Maximum freedom — unlimited daily swipes & messages',
          },
          {
            'title': 'Unlimited Backtracks & Rewinds',
            'desc': 'Undo as many swipes as you want at any time',
          },
          {
            'title': 'VIP Superlikes Pack',
            'desc': '$superlikesText with guaranteed top highlight',
          },
          {
            'title': 'Continuous Profile Boosting',
            'desc': '$boostsText to dominate discovery feeds',
          },
          {
            'title': 'Exclusive Elite VIP Crown Badge',
            'desc': 'Prestigious golden badge shown everywhere across Lunara',
          },
          {
            'title': 'Top Search & Discovery Ranking',
            'desc': 'Guaranteed #1 placement in city and nightlife search results',
          },
          {
            'title': 'Unlimited Party Plans & VIP Events',
            'desc': 'Host unlimited public & private party plans with featured badges',
          },
          {
            'title': 'Who Liked / Viewed Me (Real-Time)',
            'desc': 'Instant real-time notifications and full profiles unmasked',
          },
          {
            'title': 'VIP Concierge & Early Access',
            'desc': 'Direct priority customer support & early beta features',
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


  // ── Feature icon/color/unit helpers ─────────────────────────────────────
  String _normalizeFeatureKey(String featureKey) {
    switch (featureKey.toLowerCase()) {
      case 'boost':
      case 'profile_boost':
      case 'boosts':
        return 'boost';
      case 'superlike':
      case 'super_likes':
      case 'superlikes':
        return 'superlike';
      case 'swipe':
      case 'swipes':
        return 'swipe';
      case 'like':
      case 'likes':
        return 'like';
      case 'party_plan':
      case 'party_creation':
      case 'party_plans':
        return 'party_plan';
      case 'undo':
      case 'backtrack':
      case 'backtracks':
        return 'undo';
      default:
        return featureKey.toLowerCase();
    }
  }

  IconData _addonIcon(String featureKey) {
    switch (_normalizeFeatureKey(featureKey)) {
      case 'superlike': return Icons.star_rounded;
      case 'boost': return Icons.bolt_rounded;
      case 'swipe': return Icons.swipe_rounded;
      case 'like': return Icons.favorite_rounded;
      case 'party_plan': return Icons.celebration_rounded;
      case 'undo': return Icons.undo_rounded;
      default: return Icons.add_circle_outline_rounded;
    }
  }

  Color _addonColor(String featureKey) {
    switch (_normalizeFeatureKey(featureKey)) {
      case 'superlike': return const Color(0xFF2563EB);
      case 'boost': return const Color(0xFF8B5CF6);
      case 'swipe': return const Color(0xFF0891B2);
      case 'like': return const Color(0xFFE11D48);
      case 'party_plan': return const Color(0xFF7C3AED);
      case 'undo': return const Color(0xFFD97706);
      default: return const Color(0xFF6B7280);
    }
  }

  String _addonUnit(String featureKey) {
    switch (_normalizeFeatureKey(featureKey)) {
      case 'superlike': return 'Superlikes';
      case 'boost': return 'Boosts';
      case 'swipe': return 'Swipes';
      case 'like': return 'Likes';
      case 'party_plan': return 'Party Plans';
      case 'undo': return 'Backtracks';
      default: return 'Credits';
    }
  }

  int _currentBalance(String featureKey) {
    final norm = _normalizeFeatureKey(featureKey);
    final summary = SubscriptionProvider.instance.entitlementsSummary;
    if (summary == null) {
      if (norm == 'superlike') return SubscriptionProvider.instance.superlikesRemaining;
      if (norm == 'boost') return SubscriptionProvider.instance.boostsRemaining;
      if (norm == 'undo') return SubscriptionProvider.instance.backtracksRemaining;
      if (norm == 'party_plan') return SubscriptionProvider.instance.partyPlansRemaining;
      return 0;
    }
    switch (norm) {
      case 'superlike': return summary.superlikesAvailable;
      case 'boost': return summary.boostsAvailable;
      case 'like':
        final l = summary.likesAvailable;
        return l is int ? l : (int.tryParse(l?.toString() ?? '0') ?? 7);
      case 'party_plan':
        final p = summary.partyPlansAvailable;
        return p is int ? p : (int.tryParse(p?.toString() ?? '0') ?? 0);
      case 'undo': return summary.backtracksAvailable;
      default:
        final t = summary.totals['${norm}Available'] ?? summary.totals['${featureKey}Available'];
        if (t is int) return t;
        return int.tryParse(t?.toString() ?? '0') ?? 0;
    }
  }

  Widget _buildAddonsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isElite = _activePackageTier == 'ELITE' || SubscriptionProvider.instance.status.isElite;

    return RefreshIndicator(
      color: LunaraTheme.electricViolet,
      onRefresh: () async {
        await SubscriptionProvider.instance.fetchEntitlementsSummary(force: true);
        await _loadAddons();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFA855F7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ADD-ON STORE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  const Text('Power up your experience', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _addonBalanceBadge(
                        Icons.star_rounded,
                        isElite ? 'Unlimited' : '${_currentBalance('superlike')}',
                        'Superlikes',
                        const Color(0xFF93C5FD),
                      ),
                      _addonBalanceBadge(
                        Icons.bolt_rounded,
                        isElite ? 'Unlimited' : '${_currentBalance('boost')}',
                        'Boosts',
                        Colors.amber,
                      ),
                      _addonBalanceBadge(
                        Icons.undo_rounded,
                        isElite ? 'Unlimited' : '${_currentBalance('undo')}',
                        'Backtracks',
                        const Color(0xFFF59E0B),
                      ),
                      _addonBalanceBadge(
                        Icons.celebration_rounded,
                        isElite ? 'Unlimited' : '${_currentBalance('party_plan')}',
                        'Party Plans',
                        const Color(0xFFA78BFA),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isElite) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB703).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFB703).withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFFFB703),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your Elite VIP Plan includes unlimited boosts, superlikes, backtracks, and party plans!',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('AVAILABLE ADD-ONS', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                if (_isLoadingAddons) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: LunaraTheme.electricViolet)),
              ],
            ),
            const SizedBox(height: 14),
            if (_availableAddons.isEmpty && !_isLoadingAddons)
              _buildAddonsEmptyState(isDark)
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _availableAddons.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _buildAddonCard(_availableAddons[index], isDark),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _addonBalanceBadge(IconData icon, String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(count, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, height: 1.1)),
              Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddonCard(SubscriptionAddonPackageModel addon, bool isDark) {
    final normKey = _normalizeFeatureKey(addon.featureKey);
    final color = _addonColor(normKey);
    final icon = _addonIcon(normKey);
    final unit = _addonUnit(normKey);
    final isElite = _activePackageTier == 'ELITE' || SubscriptionProvider.instance.status.isElite;
    final bool isUnlimitedForUser = isElite &&
        (normKey == 'boost' ||
            normKey == 'superlike' ||
            normKey == 'swipe' ||
            normKey == 'like' ||
            normKey == 'party_plan');
    final balance = _currentBalance(normKey);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: isDark ? 0.12 : 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.75), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(addon.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                    if (addon.badge != null && addon.badge!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text(addon.badge!, style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(addon.description ?? '+${addon.quantity} $unit', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      isUnlimitedForUser
                          ? Icons.workspace_premium_rounded
                          : Icons.account_circle_rounded,
                      size: 13,
                      color: isUnlimitedForUser ? const Color(0xFFFFB703) : color.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isUnlimitedForUser
                          ? 'Included in Elite VIP'
                          : 'Balance: $balance $unit',
                      style: TextStyle(
                        color: isUnlimitedForUser ? const Color(0xFFFFB703) : color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isUnlimitedForUser ? 'INCLUDED' : '₹${addon.price.toStringAsFixed(0)}',
                style: TextStyle(
                  color: isUnlimitedForUser ? const Color(0xFFFFB703) : color,
                  fontSize: isUnlimitedForUser ? 11 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: isUnlimitedForUser
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB703).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFB703).withValues(alpha: 0.5), width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Color(0xFFFFB703), size: 14),
                            SizedBox(width: 4),
                            Text(
                              'UNLIMITED',
                              style: TextStyle(
                                color: Color(0xFFFFB703),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        onPressed: (_isProcessing && _pendingAddonPackageId != addon.id) ? null : () => _purchaseAddon(addon),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          elevation: 0,
                        ),
                        child: (_isProcessing && _pendingAddonPackageId == addon.id)
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('BUY', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _purchaseAddon(SubscriptionAddonPackageModel addon) async {
    final normKey = _normalizeFeatureKey(addon.featureKey);
    final isElite = _activePackageTier == 'ELITE' || SubscriptionProvider.instance.status.isElite;
    final bool isUnlimitedForUser = isElite &&
        (normKey == 'boost' ||
            normKey == 'superlike' ||
            normKey == 'swipe' ||
            normKey == 'like' ||
            normKey == 'undo' ||
            normKey == 'party_plan');

    if (isUnlimitedForUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${addon.name} is already unlimited with your Elite VIP Plan! ✨'),
          backgroundColor: const Color(0xFF7C3AED),
        ),
      );
      return;
    }

    String? walletSuccessMsg;

    final sheetSuccess = await SmartCheckoutSheet.show(
      context: context,
      title: addon.name,
      subtitle: '+${addon.quantity} ${_addonUnit(normKey)} · Instant credit',
      itemPrice: addon.price,
      onWalletPayment: () async {
        final result = await SubscriptionProvider.instance.purchaseAddonWithWallet(addon.id);
        if (result['success'] == true) {
          walletSuccessMsg = result['message'];
          return true;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message'] ?? 'Wallet payment failed.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return false;
        }
      },
      onDirectPayment: () async { await _launchRazorpayForAddon(addon); },
      onHybridPayment: (shortfallAmount) async {
        final orderData = await ApiService.createWalletRechargeOrder(shortfallAmount);
        if (orderData != null) {
          _pendingAddonPackageId = addon.id;
          _razorpay.open({
            'key': orderData['keyId'] ?? 'rzp_test_key',
            'amount': (shortfallAmount * 100).toInt(),
            'name': 'Lunara Top-Up',
            'description': 'Top up for ${addon.name}',
            'order_id': orderData['orderId'] ?? orderData['id'] ?? '',
            'theme': {'color': '#7C3AED'},
          });
        }
      },
    );

    if (sheetSuccess == true && mounted) {
      await SubscriptionProvider.instance.fetchEntitlementsSummary(force: true);
      await SubscriptionProvider.instance.refreshAfterPurchase();
      await _loadAddons();
      await _loadData();
      if (mounted) {
        final newBal = _currentBalance(normKey);
        TopNotificationBanner.show(
          title: 'Purchase Successful! 🎉',
          body: '${addon.name} added to your account.',
          iconData: _addonIcon(normKey),
        );
        _showSuccessDialog(
          'Purchase Successful! 🎉',
          walletSuccessMsg ?? 'Successfully added ${addon.name} to your account.',
          itemName: addon.name,
          balanceInfo: '$newBal ${_addonUnit(normKey)}',
          icon: _addonIcon(normKey),
          iconColor: _addonColor(normKey),
        );
      }
    }
  }

  Widget _buildAddonsEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: LunaraTheme.electricViolet.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.add_shopping_cart_rounded, size: 48, color: LunaraTheme.electricViolet.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 16),
            Text('No Add-ons Available', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Add-on packages are being set up.\nCheck back soon!', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45), fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadAddons,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(foregroundColor: LunaraTheme.electricViolet, side: BorderSide(color: LunaraTheme.electricViolet.withValues(alpha: 0.4)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
        ),
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
          final isFree = (pkg != null && pkg['tier'] == 'FREE') ||
              sub['isLifetime'] == true ||
              (endDate != null && endDate.year >= 2050);

          final String planName = pkg != null
              ? (pkg['name'] ?? (isFree ? 'Free Plan' : 'VIP Plan'))
              : (isFree ? 'Free Plan' : 'Unknown Plan');
          final int duration = pkg != null ? (pkg['durationDays'] ?? 0) : 0;

          Color statusColor = Colors.grey;
          if (status == 'ACTIVE') {
            statusColor = Colors.green;
          } else if (status == 'UPCOMING') {
            statusColor = Colors.orange;
          }

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
                        isFree ? '$planName (Lifetime)' : '$planName ($duration Days)',
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
                _buildDateRow(
                  'Expiry Date',
                  isFree ? null : endDate,
                  fallbackText: isFree ? 'Lifetime / Free Tier' : 'N/A',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateRow(String label, DateTime? date, {String fallbackText = 'N/A'}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        Text(
          date != null ? '${date.day}-${date.month}-${date.year}' : fallbackText,
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
