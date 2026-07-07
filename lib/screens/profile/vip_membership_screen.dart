import 'package:flutter/material.dart';
import '../../widgets/action_button.dart';

class VIPMembershipScreen extends StatelessWidget {
  const VIPMembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('LUNARA VIP'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildTierCard(),
            const SizedBox(height: 40),
            _buildBenefits(),
            const SizedBox(height: 40),
            LunaraActionButton(
              text: 'UPGRADE NOW',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.amber, Colors.orange],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        children: [
          Icon(Icons.star, color: Colors.white, size: 60),
          SizedBox(height: 16),
          Text(
            'GOLD MEMBER',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'Enjoy exclusive benefits',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefits() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('YOUR BENEFITS', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _benefitItem(Icons.bolt, 'Priority Entry', 'Skip the line at any venue'),
        _benefitItem(Icons.support_agent, 'VIP Host', '24/7 personal assistance'),
        _benefitItem(Icons.celebration, 'Exclusive Invites', 'Access to private parties'),
      ],
    );
  }

  Widget _benefitItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.amber),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(desc, style: const TextStyle(color: Colors.black, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
