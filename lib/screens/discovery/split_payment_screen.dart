import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import 'digital_ticket_screen.dart';

class SplitPaymentScreen extends StatefulWidget {
  const SplitPaymentScreen({super.key});

  @override
  State<SplitPaymentScreen> createState() => _SplitPaymentScreenState();
}

class _SplitPaymentScreenState extends State<SplitPaymentScreen> {
  final List<Map<String, dynamic>> _friends = [
    {
      'name': 'Alex R.',
      'amount': 250.0,
      'paid': true,
      'avatar': 'https://i.pravatar.cc/150?u=a1',
    },
    {
      'name': 'Sarah J.',
      'amount': 250.0,
      'paid': true,
      'avatar': 'https://i.pravatar.cc/150?u=s2',
    },
    {
      'name': 'Mike T.',
      'amount': 250.0,
      'paid': false,
      'avatar': 'https://i.pravatar.cc/150?u=m3',
    },
    {
      'name': 'Lily W.',
      'amount': 250.0,
      'paid': false,
      'avatar': 'https://i.pravatar.cc/150?u=l4',
    },
    {
      'name': 'You',
      'amount': 250.0,
      'paid': true,
      'avatar': 'https://i.pravatar.cc/150?u=u5',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    _buildProgressCard(),
                    const SizedBox(height: 40),
                    _buildFriendsList(),
                    const SizedBox(height: 40),
                    _buildInviteRow(),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          const Text(
            'SPLIT PAYMENT',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    double totalPaid = _friends
        .where((f) => f['paid'])
        .fold(0, (sum, f) => sum + f['amount']);
    double total = _friends.fold(0, (sum, f) => sum + f['amount']);
    double percent = totalPaid / total;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL COLLECTED',
                style: TextStyle(
                  color: Colors.grey[600],
                  height: 1.4,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '₹${totalPaid.toInt()} / ₹${total.toInt()}',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.grey[100],
              color: LunaraTheme.electricViolet,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Waiting for 2 more payments...',
            style: TextStyle(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FRIENDS IN BOAT',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 20),
        ..._friends.map((friend) => _friendTile(friend)),
      ],
    );
  }

  Widget _friendTile(Map<String, dynamic> friend) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: friend['paid'] ? LunaraTheme.electricViolet.withValues(alpha: 0.1) : Colors.grey[100]!,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[100],
              backgroundImage: NetworkImage(friend['avatar']),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend['name'],
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${friend['amount'].toInt()}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: friend['paid']
                    ? LunaraTheme.electricViolet.withValues(alpha: 0.1)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                friend['paid'] ? 'PAID' : 'PENDING',
                style: TextStyle(
                  color: friend['paid']
                      ? LunaraTheme.electricViolet
                      : Colors.grey[400],
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteRow() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: LunaraTheme.electricViolet,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            const Text(
              'Invite more friends',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: LunaraActionButton(
        text: 'SECURE RESERVATION',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const DigitalTicketScreen(),
            ),
          );
        },
      ),
    );
  }
}
