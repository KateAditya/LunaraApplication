import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

class LunaraWalletScreen extends StatefulWidget {
  const LunaraWalletScreen({super.key});

  @override
  State<LunaraWalletScreen> createState() => _LunaraWalletScreenState();
}

class _LunaraWalletScreenState extends State<LunaraWalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _filterTabController;
  late Razorpay _razorpay;
  String? _pendingOrderId;
  double _pendingRechargeAmount = 0.0;

  bool _isLoading = true;
  bool _isRecharging = false;

  Map<String, dynamic> _walletData = {};
  List<dynamic> _transactions = [];
  Map<String, dynamic> _summary = {};

  final TextEditingController _customRechargeController = TextEditingController();
  double _selectedRechargeAmount = 500.0;

  @override
  void initState() {
    super.initState();
    _filterTabController = TabController(length: 5, vsync: this);
    _filterTabController.addListener(() {
      if (mounted) setState(() {});
    });

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    _loadWalletData();
  }

  @override
  void dispose() {
    _filterTabController.dispose();
    _customRechargeController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _loadWalletData() async {
    setState(() => _isLoading = true);
    final data = await ApiService.fetchWalletData();
    if (mounted) {
      if (data != null) {
        setState(() {
          _walletData = data['wallet'] ?? {};
          _summary = data['summary'] ?? {};
          
          // Combine all transaction types for modern filter tabs
          final txns = (data['transactions'] as List? ?? []);
          final subTxns = (data['subscriptionTransactions'] as List? ?? []);
          final smartTxns = (data['smartTransactions'] as List? ?? []);

          final combined = <Map<String, dynamic>>[];

          for (final t in smartTxns) {
            combined.add(Map<String, dynamic>.from(t));
          }
          for (final t in txns) {
            combined.add(Map<String, dynamic>.from(t));
          }
          for (final t in subTxns) {
            final map = Map<String, dynamic>.from(t);
            map['type'] = 'subscription';
            combined.add(map);
          }

          // Sort by createdAt descending
          combined.sort((a, b) {
            final dateA = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(1970);
            final dateB = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(1970);
            return dateB.compareTo(dateA);
          });

          _transactions = combined;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load wallet data. Please check connection.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _openRechargeSheet([double? defaultAmount]) {
    if (defaultAmount != null) {
      _selectedRechargeAmount = defaultAmount;
      _customRechargeController.text = defaultAmount.toStringAsFixed(0);
    } else {
      _selectedRechargeAmount = 500.0;
      _customRechargeController.text = '500';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_card_rounded,
                          color: LunaraTheme.electricViolet,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Recharge Wallet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Instant digital credit for VIP, Boosts & Likes',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SELECT AMOUNT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [100, 250, 500, 1000, 2000].map((amt) {
                      final isSelected = _selectedRechargeAmount == amt.toDouble();
                      return ChoiceChip(
                        label: Text(
                          '₹$amt',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: LunaraTheme.electricViolet,
                        backgroundColor: Colors.grey[100],
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected ? LunaraTheme.electricViolet : Colors.transparent,
                          ),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() {
                              _selectedRechargeAmount = amt.toDouble();
                              _customRechargeController.text = amt.toString();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _customRechargeController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Custom Amount (₹)',
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: LunaraTheme.electricViolet,
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey[200]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: LunaraTheme.electricViolet, width: 2),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = double.tryParse(val);
                      if (parsed != null) {
                        setModalState(() {
                          _selectedRechargeAmount = parsed;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isRecharging
                          ? null
                          : () async {
                              final amt = double.tryParse(_customRechargeController.text) ?? _selectedRechargeAmount;
                              if (amt < 100) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Minimum recharge amount is ₹100')),
                                );
                                return;
                              }
                              Navigator.pop(context);
                              await _executeRecharge(amt);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isRecharging
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'PROCEED TO PAY ₹${_selectedRechargeAmount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: Colors.white,
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
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) async {
    setState(() => _isRecharging = true);
    try {
      final success = await ApiService.verifyWalletRecharge(
        amount: _pendingRechargeAmount,
        razorpayPaymentId: response.paymentId ?? '',
        razorpayOrderId: response.orderId ?? _pendingOrderId,
        razorpaySignature: response.signature,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Verified! Recharged ₹${_pendingRechargeAmount.toStringAsFixed(0)} 💳'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
        await _loadWalletData();
      } else {
        throw Exception('Payment verification failed on backend');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecharging = false);
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() => _isRecharging = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment Cancelled / Failed: ${response.message ?? "User cancelled payment"}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted) {
      setState(() => _isRecharging = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('External Wallet selected: ${response.walletName}')),
      );
    }
  }

  Future<void> _executeRecharge(double amount) async {
    setState(() => _isRecharging = true);
    _pendingRechargeAmount = amount;

    try {
      final orderData = await ApiService.createWalletRechargeOrder(amount);
      if (orderData == null) {
        throw Exception('Failed to generate secure Razorpay order from server.');
      }

      final String orderId = orderData['orderId'] ?? orderData['id'] ?? '';
      _pendingOrderId = orderId;

      final options = {
        'key': orderData['keyId'] ?? 'rzp_test_key',
        'amount': (amount * 100).toInt(),
        'name': 'Lunara Wallet',
        'description': 'Smart Credit Wallet Recharge',
        'order_id': orderId,
        'prefill': {
          'contact': orderData['userMobile'] ?? '',
          'email': orderData['userEmail'] ?? '',
        },
        'theme': {'color': '#7F00FF'},
      };

      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error launching Razorpay Gateway: $e');
      if (mounted) {
        setState(() => _isRecharging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recharge Gateway Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double availableBalance = double.tryParse(
          (_walletData['availableBalance'] ?? _walletData['balance'] ?? 0.0).toString(),
        ) ??
        0.0;
    final bool isFrozen = _walletData['isFrozen'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadWalletData,
          color: LunaraTheme.electricViolet,
          child: Column(
            children: [
              _buildCleanHeader(context),
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (availableBalance < 100) _buildLowBalanceBanner(),
                        _buildMasterBalanceCard(availableBalance, isFrozen),
                        const SizedBox(height: 16),
                        _buildActiveMembershipCard(),
                        const SizedBox(height: 20),
                        _buildTransactionsSectionHeader(),
                        const SizedBox(height: 12),
                        _buildFilterTabs(),
                        const SizedBox(height: 12),
                        _buildFilteredTransactionsList(),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCleanHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'My Wallet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 0.3,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black, size: 22),
            onPressed: _loadWalletData,
          ),
        ],
      ),
    );
  }

  Widget _buildLowBalanceBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Wallet Balance Low',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF92400E),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Recharge now to continue using VIP & premium features.',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _openRechargeSheet(500),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Recharge',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterBalanceCard(double availableBalance, bool isFrozen) {
    final double rawRecharged = double.tryParse((_walletData['lifetimeRecharged'] ?? 0.0).toString()) ?? 0.0;
    final double summaryRecharged = double.tryParse((_summary['totalRecharged'] ?? 0.0).toString()) ?? 0.0;
    final double lifetimeRecharged = rawRecharged > 0 ? rawRecharged : summaryRecharged;

    final double rawSpent = double.tryParse((_walletData['lifetimeSpent'] ?? 0.0).toString()) ?? 0.0;
    final double summarySpent = double.tryParse((_summary['totalSpent'] ?? 0.0).toString()) ?? 0.0;
    final double lifetimeSpent = rawSpent > 0 ? rawSpent : summarySpent;

    final double rewardCredits = double.tryParse(
          (_walletData['rewardBalance'] ?? _walletData['lifetimeRewards'] ?? 0.0).toString(),
        ) ??
        0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1035), Color(0xFF2E1B4E), Color(0xFF150A26)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1035).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wallet Status & Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AVAILABLE BALANCE',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isFrozen ? Colors.red.withValues(alpha: 0.2) : const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFrozen ? Colors.redAccent : const Color(0xFF10B981),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isFrozen ? Colors.redAccent : const Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isFrozen ? 'Suspended' : 'Wallet Active',
                      style: TextStyle(
                        color: isFrozen ? Colors.redAccent : const Color(0xFF10B981),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Large Balance Display
          Text(
            '₹${availableBalance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          // Recharge Wallet CTA Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _openRechargeSheet(),
              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
              label: const Text(
                'RECHARGE WALLET',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          // Lifetime Stats Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _balanceStatItem('LIFETIME RECHARGE', '₹${lifetimeRecharged.toStringAsFixed(0)}', const Color(0xFF10B981)),
              Container(height: 26, width: 1, color: Colors.white.withValues(alpha: 0.1)),
              _balanceStatItem('SPENT', '₹${lifetimeSpent.toStringAsFixed(0)}', const Color(0xFFF43F5E)),
              Container(height: 26, width: 1, color: Colors.white.withValues(alpha: 0.1)),
              _balanceStatItem('REWARDS', '₹${rewardCredits.toStringAsFixed(0)}', const Color(0xFFF59E0B)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveMembershipCard() {
    final Map<String, dynamic> sub = _walletData['currentMembership'] ?? {};
    final String tier = (sub['tier'] ?? 'FREE').toString().toUpperCase();
    final String name = sub['packageName'] ?? 'Free Plan';
    final bool isActive = sub['status'] == 'active' || tier != 'FREE';

    if (!isActive) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VIP $tier MEMBERSHIP',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/subscriptions'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Manage',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSectionHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        'TRANSACTIONS',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 36,
      child: TabBar(
        controller: _filterTabController,
        isScrollable: true,
        indicator: BoxDecoration(
          color: LunaraTheme.electricViolet,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey[600],
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Recharge'),
          Tab(text: 'Membership'),
          Tab(text: 'Rewards'),
          Tab(text: 'Purchases'),
        ],
      ),
    );
  }

  Widget _buildFilteredTransactionsList() {
    final filterIndex = _filterTabController.index;
    final filtered = _transactions.where((txn) {
      final type = (txn['transactionType'] ?? txn['type'] ?? '').toString().toLowerCase();
      if (filterIndex == 1) return type.contains('recharge');
      if (filterIndex == 2) return type.contains('vip') || type.contains('subscription') || type.contains('membership');
      if (filterIndex == 3) return type.contains('reward') || type.contains('cashback') || type.contains('promo');
      if (filterIndex == 4) return type.contains('purchase') || type.contains('booking') || type.contains('deposit');
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_rounded, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              const Text(
                'No Transactions Found',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
              ),
              const SizedBox(height: 4),
              Text(
                'Transactions matching this filter will appear here.',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        return _buildCompactTransactionCard(filtered[index]);
      },
    );
  }

  Widget _buildCompactTransactionCard(Map<String, dynamic> txn) {
    final double amount = double.tryParse(txn['amount']?.toString() ?? '0.0') ?? 0.0;
    final String rawStatus = (txn['status'] ?? 'success').toString().toLowerCase();
    final String type = (txn['transactionType'] ?? txn['type'] ?? 'payment').toString().toLowerCase();
    final contextData = txn['context'] ?? {};

    String title = 'TRANSACTION';
    IconData icon = Icons.receipt_rounded;
    Color iconBg = Colors.grey[100]!;
    Color iconColor = Colors.grey[800]!;

    bool isCredit = type.contains('recharge') || type.contains('credit') || type.contains('cashback') || type.contains('reward');

    if (type.contains('recharge')) {
      title = 'RECHARGE';
      icon = Icons.add_card_rounded;
      iconBg = Colors.blue.withValues(alpha: 0.1);
      iconColor = Colors.blue[700]!;
    } else if (type.contains('vip') || type.contains('subscription')) {
      title = (contextData['planName'] ?? 'VIP MEMBERSHIP').toString().toUpperCase();
      icon = Icons.workspace_premium_rounded;
      iconBg = const Color(0xFFE100FF).withValues(alpha: 0.1);
      iconColor = const Color(0xFFE100FF);
    } else if (type.contains('super_like')) {
      title = 'SUPER LIKES';
      icon = Icons.star_rounded;
      iconBg = Colors.amber.withValues(alpha: 0.1);
      iconColor = Colors.amber[800]!;
    } else if (type.contains('boost')) {
      title = 'PROFILE BOOST';
      icon = Icons.bolt_rounded;
      iconBg = Colors.blueAccent.withValues(alpha: 0.1);
      iconColor = Colors.blueAccent;
    } else if (type.contains('reward') || type.contains('cashback')) {
      title = 'REWARD CREDIT';
      icon = Icons.card_giftcard_rounded;
      iconBg = const Color(0xFF10B981).withValues(alpha: 0.1);
      iconColor = const Color(0xFF10B981);
    } else {
      title = (contextData['venueName'] ?? 'TABLE BOOKING').toString().toUpperCase();
      icon = Icons.local_activity_rounded;
      iconBg = LunaraTheme.electricViolet.withValues(alpha: 0.1);
      iconColor = LunaraTheme.electricViolet;
    }

    String dateStr = 'Today';
    if (txn['createdAt'] != null) {
      try {
        final dt = DateTime.parse(txn['createdAt']).toLocal();
        dateStr = DateFormat('d MMM • h:mm a').format(dt);
      } catch (_) {}
    }

    Color statusColor = const Color(0xFF10B981);
    String statusLabel = 'SUCCESS';

    if (rawStatus == 'pending' || rawStatus == 'processing') {
      statusColor = Colors.orange;
      statusLabel = 'PENDING';
    } else if (rawStatus == 'failed' || rawStatus == 'cancelled') {
      statusColor = Colors.redAccent;
      statusLabel = 'FAILED';
    } else if (rawStatus == 'locked') {
      statusColor = Colors.amber;
      statusLabel = 'LOCKED';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? "+" : "-"}₹${amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isCredit ? const Color(0xFF10B981) : Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
