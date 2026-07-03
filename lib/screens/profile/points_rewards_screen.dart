import 'package:flutter/material.dart';
import '../../core/theme.dart';

class PointsRewardsScreen extends StatelessWidget {
  const PointsRewardsScreen({super.key});

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
                    _buildPointsProgress(),
                    const SizedBox(height: 48),
                    _buildRewardsMarketplace(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'LUNARA POINTS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const Icon(Icons.info_outline, color: Colors.grey, size: 20),
        ],
      ),
    );
  }

  Widget _buildPointsProgress() {
    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: 0.75,
                strokeWidth: 12,
                backgroundColor: Colors.grey[100],
                color: LunaraTheme.electricViolet,
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '4,850',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      'TOTAL POINTS',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          '1,150 MORE TO PLATINUM',
          style: TextStyle(
            color: LunaraTheme.electricViolet,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildRewardsMarketplace() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REWARDS MARKETPLACE',
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 24),
        _rewardTile(
          'Complimentary Drink',
          'Choose any signature cocktail.',
          '500',
          Icons.local_bar,
        ),
        _rewardTile(
          'Table Upgrade',
          'Move to VIP Lounge on your next booking.',
          '2,000',
          Icons.upgrade,
        ),
        _rewardTile(
          'Fast-Track Entry',
          'Priority access for you + 2 friends.',
          '1,500',
          Icons.bolt,
        ),
        _rewardTile(
          'Birthday Package',
          'Sparklers, custom cake, and round of shots.',
          '5,000',
          Icons.cake,
        ),
      ],
    );
  }

  Widget _rewardTile(String title, String desc, String cost, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: LunaraTheme.premiumCardShadow,
          border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: LunaraTheme.electricViolet, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(color: Colors.black, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$cost PTS',
                style: const TextStyle(
                  color: LunaraTheme.electricViolet,
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
}
