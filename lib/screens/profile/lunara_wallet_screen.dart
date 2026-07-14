import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

class LunaraWalletScreen extends StatefulWidget {
  const LunaraWalletScreen({super.key});

  @override
  State<LunaraWalletScreen> createState() => _LunaraWalletScreenState();
}

class _LunaraWalletScreenState extends State<LunaraWalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<dynamic> _incompleteEvents = [];
  List<dynamic> _transactions = [];
  Map<String, dynamic> _summary = {
    'totalIncompleteEvents': 0,
    'totalTransactions': 0,
    'totalSpent': 0.0,
    'totalRefunded': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadWalletData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWalletData() async {
    setState(() => _isLoading = true);
    final data = await ApiService.fetchWalletData();
    if (mounted) {
      if (data != null) {
        setState(() {
          _incompleteEvents = data['incompleteEvents'] ?? [];
          _transactions = data['transactions'] ?? [];
          _summary = data['summary'] ?? _summary;
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

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadWalletData,
          color: LunaraTheme.electricViolet,
          child: Column(
            children: [
              _buildHeader(context),
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  ),
                )
              else ...[
                _buildWalletCard(),
                const SizedBox(height: 20),
                _buildTabBar(),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildIncompleteEventsList(),
                      _buildTransactionsList(),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'LUNARA WALLET',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black),
            onPressed: _loadWalletData,
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    final double totalSpent = double.tryParse(_summary['totalSpent'].toString()) ?? 0.0;
    final double totalRefunded = double.tryParse(_summary['totalRefunded'].toString()) ?? 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A1B3D),
            Color(0xFF1E122A),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A1B3D).withOpacity(0.35),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL SPENT',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${totalSpent.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: LunaraTheme.electricViolet,
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _walletStatItem('TOTAL REFUNDED', '₹${totalRefunded.toStringAsFixed(2)}', const Color(0xFF10B981)),
              Container(
                height: 30,
                width: 1,
                color: Colors.white.withOpacity(0.1),
              ),
              _walletStatItem(
                'INCOMPLETE EVENTS',
                '${_incompleteEvents.length}',
                Colors.amber,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletStatItem(String label, String value, Color highlightColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: highlightColor,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(18),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelColor: Colors.black,
        unselectedLabelColor: Colors.grey[500],
        labelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'INCOMPLETE'),
          Tab(text: 'TRANSACTIONS'),
        ],
      ),
    );
  }

  Widget _buildIncompleteEventsList() {
    if (_incompleteEvents.isEmpty) {
      return _buildEmptyState(
        Icons.event_busy_rounded,
        'No Incomplete Events',
        'All your deposit plans and bookings are completed or inactive.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: _incompleteEvents.length,
      itemBuilder: (context, index) {
        final event = _incompleteEvents[index];
        return _buildIncompleteEventCard(event);
      },
    );
  }

  Widget _buildIncompleteEventCard(Map<String, dynamic> event) {
    final venue = event['venue'] ?? {};
    final String venueName = venue['name'] ?? 'Premium Club';
    final String venueArea = venue['area'] ?? venue['city'] ?? 'City Center';
    final double deposit = double.tryParse(event['depositAmount']?.toString() ?? '99.00') ?? 99.00;
    final String role = (event['role'] ?? 'host').toString().toUpperCase();
    final String waitingFor = event['waitingFor'] ?? 'Participant Payment';
    final String coverImage = venue['coverImage'] ?? 'https://picsum.photos/seed/lunara/600/400';

    final isHost = role == 'HOST';

    // Format DateTime
    String dateStr = 'TBD';
    if (event['planDateTime'] != null) {
      try {
        final dt = DateTime.parse(event['planDateTime']);
        dateStr = DateFormat('EEE, MMM d • h:mm a').format(dt).toUpperCase();
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Venue Image Header
            Container(
              height: 120,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(coverImage),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(16),
                alignment: Alignment.bottomLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            venueName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            venueArea.toUpperCase(),
                            style: const TextStyle(
                              color: LunaraTheme.electricViolet,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isHost ? LunaraTheme.electricViolet : Colors.teal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        role,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Card Body Info
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SAFETY DEPOSIT PAID',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${deposit.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              waitingFor.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF8A6D00),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(color: Colors.grey[100]),
                  const SizedBox(height: 6),
                  
                  // Interactive info about other party
                  _buildIncompletePartyDetail(event),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncompletePartyDetail(Map<String, dynamic> event) {
    final String role = (event['role'] ?? 'host').toString().toLowerCase();
    final isHost = role == 'host';

    if (isHost) {
      final joiner = event['joiner'];
      if (joiner != null) {
        final String name = joiner['name'] ?? 'Joiner';
        final String? avatar = joiner['profileImageUrl'];
        return Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey[200],
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? const Icon(Icons.person, size: 12, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Waiting for joiner $name to pay.',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        );
      } else {
        final int count = event['pendingRequestCount'] ?? 0;
        return Row(
          children: [
            const Icon(Icons.people_outline_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                count > 0
                    ? '$count joiner requests waiting for your acceptance.'
                    : 'Awaiting participants to apply to your party plan.',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        );
      }
    } else {
      final host = event['host'];
      final String hostName = host != null ? (host['name'] ?? 'Host') : 'Host';
      final String? avatar = host?['profileImageUrl'];
      return Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.grey[200],
            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
            child: avatar == null
                ? const Icon(Icons.person, size: 12, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Awaiting confirmation from host $hostName.',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildTransactionsList() {
    if (_transactions.isEmpty) {
      return _buildEmptyState(
        Icons.receipt_long_rounded,
        'No Transactions Yet',
        'Your transaction history is currently empty.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final txn = _transactions[index];
        return _buildTransactionItem(txn);
      },
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> txn) {
    final double amount = double.tryParse(txn['amount']?.toString() ?? '0.0') ?? 0.0;
    final String status = (txn['status'] ?? 'successful').toString().toLowerCase();
    final String type = txn['type'] ?? 'payment';
    final contextData = txn['context'] ?? {};
    final String venueName = contextData['venueName'] ?? 'Lunara Booking';

    // Format Date
    String dateStr = 'TBD';
    if (txn['createdAt'] != null) {
      try {
        final dt = DateTime.parse(txn['createdAt']);
        dateStr = DateFormat('MMM d, yyyy • h:mm a').format(dt);
      } catch (_) {}
    }

    IconData icon;
    Color iconBg;
    Color iconColor;
    String displayTitle;

    if (type == 'party_plan_deposit') {
      icon = Icons.security_rounded;
      iconBg = Colors.amber.withOpacity(0.1);
      iconColor = Colors.amber[800]!;
      displayTitle = contextData['label'] ?? 'Safety Deposit';
    } else {
      icon = Icons.local_activity_rounded;
      iconBg = LunaraTheme.electricViolet.withOpacity(0.1);
      iconColor = LunaraTheme.electricViolet;
      displayTitle = 'Table Booking';
    }

    Color statusColor;
    if (status == 'successful' || status == 'success') {
      statusColor = const Color(0xFF10B981);
    } else if (status == 'refunded') {
      statusColor = Colors.blueAccent;
    } else {
      statusColor = Colors.redAccent;
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: () => _showTransactionDetailsBottomSheet(txn),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          displayTitle.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.5,
            color: Colors.black,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              venueName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionDetailsBottomSheet(Map<String, dynamic> txn) {
    final double amount = double.tryParse(txn['amount']?.toString() ?? '0.0') ?? 0.0;
    final double refundAmount = double.tryParse(txn['refundAmount']?.toString() ?? '0.0') ?? 0.0;
    final String status = (txn['status'] ?? 'successful').toString().toUpperCase();
    final String method = (txn['paymentMethod'] ?? 'razorpay').toString().toUpperCase();
    final String txnId = txn['txnId'] ?? 'N/A';
    final String type = txn['type'] ?? 'booking';
    final contextData = txn['context'] ?? {};
    final String venueName = contextData['venueName'] ?? 'Lunara Partner Venue';
    final String venueCity = contextData['venueCity'] ?? '';

    String dateStr = 'N/A';
    if (txn['createdAt'] != null) {
      try {
        final dt = DateTime.parse(txn['createdAt']);
        dateStr = DateFormat('MMMM d, yyyy • h:mm a').format(dt);
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'TRANSACTION DETAILS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Text(
                      '₹${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: status == 'SUCCESSFUL' || status == 'SUCCESS'
                            ? const Color(0xFF10B981)
                            : status == 'REFUNDED'
                                ? Colors.blueAccent
                                : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _detailRow('VENUE', venueName),
              if (venueCity.isNotEmpty) _detailRow('LOCATION', venueCity),
              _detailRow('TRANSACTION ID', txnId),
              _detailRow('DATE & TIME', dateStr),
              _detailRow('PAYMENT METHOD', method),
              _detailRow('TYPE', type == 'party_plan_deposit' ? 'Safety Deposit' : 'Booking Payment'),
              if (refundAmount > 0)
                _detailRow('REFUND AMOUNT', '₹${refundAmount.toStringAsFixed(2)}'),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: constraints.maxHeight,
            padding: const EdgeInsets.all(24.0),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 48, color: Colors.grey[350]),
                ),
                const SizedBox(height: 20),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
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
