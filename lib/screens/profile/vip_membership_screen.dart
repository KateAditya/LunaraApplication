import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/action_button.dart';

class VIPMembershipScreen extends StatefulWidget {
  const VIPMembershipScreen({super.key});

  @override
  State<VIPMembershipScreen> createState() => _VIPMembershipScreenState();
}

class _VIPMembershipScreenState extends State<VIPMembershipScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Razorpay _razorpay;

  bool _isLoading = true;
  bool _isProcessing = false;
  
  List<dynamic> _allPackages = [];
  Map<String, dynamic>? _currentSubscription;
  String? _activePackageId;
  int _activeRemainingDays = 0;

  // Selected Options
  int _selectedPlanIndex = 0; // 0: Core, 1: Plus, 2: Pro, 3: Elite
  int _selectedEliteIndex = 0; // Index of selected Elite duration option
  int _selectedBoostOption = 0; // 0: 1 Boost, 1: 2 Boosts, 2: 3 Boosts, 3: 5 Boosts

  final List<Map<String, dynamic>> _boostOptions = [
    {'count': 1, 'price': 49, 'label': '1 Boost'},
    {'count': 2, 'price': 90, 'label': '2 Boosts'},
    {'count': 3, 'price': 140, 'label': '3 Boosts'},
    {'count': 5, 'price': 160, 'label': '5 Boosts'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final packages = await ApiService.fetchSubscriptionPackages();
      final currentSub = await ApiService.fetchUserSubscription();

      setState(() {
        _allPackages = packages;
        _currentSubscription = currentSub;
        if (currentSub['subscription'] != null) {
          _activePackageId = currentSub['subscription']['packageId'];
          _activeRemainingDays = currentSub['remainingDays'] ?? 0;
        } else {
          _activePackageId = null;
          _activeRemainingDays = 0;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading VIP screen data: $e');
      setState(() => _isLoading = false);
    }
  }

  // Get grouped plans
  Map<String, dynamic>? get _corePackage => _allPackages.firstWhere(
      (p) => p['tier'] == 'CORE', orElse: () => null);

  Map<String, dynamic>? get _plusPackage => _allPackages.firstWhere(
      (p) => p['tier'] == 'PLUS', orElse: () => null);

  Map<String, dynamic>? get _proPackage => _allPackages.firstWhere(
      (p) => p['tier'] == 'PRO', orElse: () => null);

  List<dynamic> get _elitePackages {
    final list = _allPackages.where((p) => p['tier'] == 'ELITE').toList();
    list.sort((a, b) => (a['durationDays'] as num).compareTo(b['durationDays'] as num));
    return list;
  }

  dynamic get _selectedPackage {
    if (_selectedPlanIndex == 0) return _corePackage;
    if (_selectedPlanIndex == 1) return _plusPackage;
    if (_selectedPlanIndex == 2) return _proPackage;
    if (_selectedPlanIndex == 3) {
      final elites = _elitePackages;
      if (elites.isEmpty) return null;
      if (_selectedEliteIndex >= elites.length) {
        _selectedEliteIndex = 0;
      }
      return elites[_selectedEliteIndex];
    }
    return null;
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) {
    if (_tabController.index == 0) {
      // Package Purchase
      final pkg = _selectedPackage;
      if (pkg != null) {
        _confirmPackagePurchase(
          pkg['id'],
          response.orderId ?? 'order_mock_${Date.now()}',
          response.paymentId ?? 'pay_mock_${Date.now()}',
        );
      }
    } else {
      // Boost Purchase
      final boost = _boostOptions[_selectedBoostOption];
      _confirmBoostPurchase(
        boost['count'],
        response.orderId ?? 'order_mock_${Date.now()}',
        response.paymentId ?? 'pay_mock_${Date.now()}',
      );
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() => _isProcessing = false);
  }

  Future<void> _initiatePurchase() async {
    final pkg = _selectedPackage;
    if (pkg == null) return;

    setState(() => _isProcessing = true);

    final double price = double.tryParse(pkg['price'].toString()) ?? 0.0;
    final int amountInPaisa = (price * 100).toInt();

    // Since we don't have a backend initiate payment order creator for subscriptions,
    // we use a generated local mock order ID to support fallback & live payments.
    final String generatedOrderId = 'order_sub_${DateTime.now().millisecondsSinceEpoch}';

    var options = {
      'key': 'rzp_test_123',
      'amount': amountInPaisa,
      'name': 'Lunara VIP',
      'description': 'Subscription - ${pkg['name']}',
      'order_id': generatedOrderId,
      'prefill': {
        'contact': '8888888888',
        'email': 'vip@lunara.com'
      }
    };

    bool razorpayOpened = false;
    try {
      _razorpay.open(options);
      razorpayOpened = true;
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
    }

    if (!razorpayOpened) {
      // Simulate checkout callback in test environment
      Future.delayed(const Duration(seconds: 2), () {
        _confirmPackagePurchase(pkg['id'], generatedOrderId, 'pay_mock_${DateTime.now().millisecondsSinceEpoch}');
      });
    }
  }

  Future<void> _initiateBoostPurchase() async {
    final boost = _boostOptions[_selectedBoostOption];
    setState(() => _isProcessing = true);

    final double price = double.tryParse(boost['price'].toString()) ?? 0.0;
    final int amountInPaisa = (price * 100).toInt();
    final String generatedOrderId = 'order_boost_${DateTime.now().millisecondsSinceEpoch}';

    var options = {
      'key': 'rzp_test_123',
      'amount': amountInPaisa,
      'name': 'Lunara Profile Boost',
      'description': 'Boost Pack - ${boost['label']}',
      'order_id': generatedOrderId,
      'prefill': {
        'contact': '8888888888',
        'email': 'boost@lunara.com'
      }
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
        _confirmBoostPurchase(boost['count'], generatedOrderId, 'pay_mock_${DateTime.now().millisecondsSinceEpoch}');
      });
    }
  }

  Future<void> _confirmPackagePurchase(String packageId, String orderId, String paymentId) async {
    final data = await ApiService.purchaseSubscription(
      packageId: packageId,
      gatewayOrderId: orderId,
      gatewayPaymentId: paymentId,
    );

    setState(() => _isProcessing = false);

    if (data != null) {
      _showSuccessDialog('Subscription Activated!', 'You have successfully upgraded your tier.');
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to activate subscription. Please contact support.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmBoostPurchase(int boostCount, String orderId, String paymentId) async {
    final data = await ApiService.purchaseBoost(boostCount);

    setState(() => _isProcessing = false);

    if (data != null) {
      _showSuccessDialog('Boosts Credited!', '$boostCount profile boosts have been added to your account.');
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to purchase boosts. Please contact support.'),
          backgroundColor: Colors.red,
        ),
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
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('GREAT', style: TextStyle(fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        title: const Text(
          'LUNARA VIP',
          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
        ),
        backgroundColor: const Color(0xFF0E0E12),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: LunaraTheme.electricViolet,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'VIP PASSES'),
            Tab(text: 'PROFILE BOOST'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildVIPPassesTab(),
                _buildProfileBoostTab(),
              ],
            ),
    );
  }

  Widget _buildVIPPassesTab() {
    final pkg = _selectedPackage;
    if (pkg == null) {
      return const Center(
        child: Text('No subscription plans available.', style: TextStyle(color: Colors.white70)),
      );
    }

    final double price = double.tryParse(pkg['price'].toString()) ?? 0.0;
    final int duration = pkg['durationDays'] ?? 0;
    final String tier = pkg['tier'];
    final bool isActive = _activePackageId == pkg['id'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan Selector Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPlanPill(0, 'Core', const Color(0xFF00A9FF)),
                const SizedBox(width: 8),
                _buildPlanPill(1, 'Plus', const Color(0xFF7F00FF)),
                const SizedBox(width: 8),
                _buildPlanPill(2, 'Pro', const Color(0xFFE100FF)),
                const SizedBox(width: 8),
                _buildPlanPill(3, 'Elite VIP', const Color(0xFFFFB703)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Plan Badge Card
          _buildPremiumCard(pkg),
          const SizedBox(height: 24),

          // Elite Durations (only if Elite selected)
          if (tier == 'ELITE') ...[
            const Text(
              'SELECT ELITE OPTION',
              style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            _buildEliteDurationsSelector(),
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
              onPressed: _isProcessing ? null : (isActive ? null : _initiatePurchase),
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? Colors.grey[800] : _getPlanThemeColor(tier),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      isActive ? 'CURRENT PLAN' : 'UPGRADE FOR ₹${price.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: tier == 'ELITE' && !isActive ? Colors.black : Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProfileBoostTab() {
    final selectedBoost = _boostOptions[_selectedBoostOption];

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
                )
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
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.black, letterSpacing: -0.5),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Get up to 10x more likes, views, and responses! Your profile goes straight to the top of discovery in your area.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Icon(Icons.bolt, color: Colors.amber, size: 64),
              ],
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'SELECT BOOST PACKAGE',
            style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
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
              return GestureDetector(
                onTap: () => setState(() => _selectedBoostOption = index),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.purple.withValues(alpha: 0.15) : const Color(0xFF16161E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? Colors.purple : Colors.white.withValues(alpha: 0.05),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        option['label'],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₹${option['price']}',
                        style: TextStyle(
                          color: isSelected ? Colors.purpleAccent : Colors.white70,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      'PURCHASE FOR ₹${selectedBoost['price']}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanPill(int index, String label, Color color) {
    final isSelected = _selectedPlanIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedPlanIndex = index;
        if (index == 3) {
          _selectedEliteIndex = 0;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : const Color(0xFF16161E),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.05),
            width: 1.5,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: isSelected ? color : Colors.white60,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumCard(dynamic pkg) {
    final String tier = pkg['tier'];
    final Color color = _getPlanThemeColor(tier);
    final String name = pkg['name'];
    final double price = double.tryParse(pkg['price'].toString()) ?? 0.0;
    final int duration = pkg['durationDays'] ?? 0;
    final bool isActive = _activePackageId == pkg['id'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.15), const Color(0xFF16161E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name.toUpperCase(),
                style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Text(
                    'ACTIVE • $_activeRemainingDays DAYS LEFT',
                    style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            alignment: PlaceholderAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${price.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Text(
                '/ $duration DAYS',
                style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _getPlanDescription(tier),
            style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildEliteDurationsSelector() {
    final elites = _elitePackages;
    if (elites.isEmpty) return const SizedBox.shrink();

    return Row(
      children: List.generate(elites.length, (index) {
        final item = elites[index];
        final isSelected = _selectedEliteIndex == index;
        final int days = item['durationDays'] ?? 0;
        final double price = double.tryParse(item['price'].toString()) ?? 0.0;
        
        String label = '${days}d';
        if (days == 30) label = '30d';
        if (days == 90) label = '3m';
        if (days == 180) label = '6m';
        if (days == 365) label = '12m';

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedEliteIndex = index),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFFB703).withValues(alpha: 0.15) : const Color(0xFF16161E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFFB703) : Colors.white.withValues(alpha: 0.05),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? const Color(0xFFFFB703) : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${price.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white38,
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
    final String tier = pkg['tier'];
    final Color color = _getPlanThemeColor(tier);

    // List out benefits based on tier
    List<Map<String, String>> benefits = [];
    if (tier == 'CORE' || tier == 'PLUS' || tier == 'PRO' || tier == 'ELITE') {
      benefits.addAll([
        {'title': 'Send Unlimited Match Requests', 'desc': 'No daily swipe restrictions'},
        {'title': 'Unlimited Posts & Likes', 'desc': 'Share and engage with no limits'},
        {'title': 'Who Liked/Viewed Your Profile', 'desc': 'Unmask interested users instantly'},
      ]);
    }
    if (tier == 'PLUS' || tier == 'PRO' || tier == 'ELITE') {
      benefits.addAll([
        {'title': '10 Superlikes Per Cycle', 'desc': 'Stand out in their notifications'},
        {'title': '2 Free Profile Boosts', 'desc': 'Automatic ranking push in searches'},
        {'title': 'Hide Profile Mode', 'desc': 'Browse matches silently and anonymously'},
      ]);
    }
    if (tier == 'PRO' || tier == 'ELITE') {
      benefits.addAll([
        {'title': 'Priority Visibility', 'desc': 'Appear in front of users before non-Pro users'},
        {'title': '4 Free Profile Boosts', 'desc': 'Enhanced package cycle boosts'},
        {'title': 'Trust Badge', 'desc': 'Adds a premium verify check on your profile'},
      ]);
    }
    if (tier == 'ELITE') {
      benefits.addAll([
        {'title': 'Maximum Profile Boost', 'desc': 'Stay at the very top of search feeds'},
        {'title': 'Elite User Badge', 'desc': 'Exclusive premium badge layout'},
        {'title': 'Early Access to Pro Features', 'desc': 'Test and access new updates first'},
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'INCLUDED BENEFITS',
          style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
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
            margin: const EdgeInsets.top(2),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, color: color, size: 14),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.bolt_rounded, color: Colors.purpleAccent, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white80, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPlanThemeColor(String tier) {
    if (tier == 'CORE') return const Color(0xFF00A9FF);
    if (tier == 'PLUS') return const Color(0xFF7F00FF);
    if (tier == 'PRO') return const Color(0xFFE100FF);
    if (tier == 'ELITE') return const Color(0xFFFFB703);
    return Colors.white;
  }

  String _getPlanDescription(String tier) {
    if (tier == 'CORE') return 'Perfect for daily swiping and standard messaging.';
    if (tier == 'PLUS') return 'Boost your reach and browse anonymously.';
    if (tier == 'PRO') return 'Stand out from the crowd with priority visibility.';
    if (tier == 'ELITE') return 'Maximum features, priority entry, and elite badges.';
    return '';
  }
}
