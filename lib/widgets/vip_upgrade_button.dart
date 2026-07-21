import 'package:flutter/material.dart';
import '../screens/profile/vip_membership_screen.dart';
import '../services/api_service.dart';

class VIPUpgradeButton extends StatelessWidget {
  final double size;
  final String? tier;
  final VoidCallback? onUpdated;

  const VIPUpgradeButton({
    super.key,
    this.size = 36.0,
    this.tier,
    this.onUpdated,
  });

  /// Resolves the tier color based on user's active plan
  Color _getTierColor(String? tierName) {
    final effectiveTier = (tierName != null && tierName.isNotEmpty)
        ? tierName.toUpperCase()
        : (ApiService.cachedCurrentUser?.subscriptionTier.toUpperCase() ?? 'FREE');

    switch (effectiveTier) {
      case 'ELITE':
        return const Color(0xFFFFB703); // Royal Gold
      case 'PRO':
        return const Color(0xFFE100FF); // Neon Magenta
      case 'PLUS':
        return const Color(0xFF7F00FF); // Deep Violet
      case 'CORE':
        return const Color(0xFF00A9FF); // Cyber Cyan
      case 'FREE':
      default:
        return const Color(0xFF9E9E9E); // Sleek Grey for Free Tier
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getTierColor(tier);
    final iconSize = size * 0.65;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const VIPMembershipScreen(),
          ),
        );
        if (onUpdated != null) {
          onUpdated!();
        }
      },
      child: Container(
        height: size,
        width: size,
        alignment: Alignment.center,
        child: Image.asset(
          'assets/images/vip_bolt_icon_white.png',
          width: iconSize,
          height: iconSize,
          color: color,
        ),
      ),
    );
  }
}

