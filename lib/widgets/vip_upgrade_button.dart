import 'package:flutter/material.dart';
import '../screens/profile/vip_membership_screen.dart';

class VIPUpgradeButton extends StatelessWidget {
  final double size;

  const VIPUpgradeButton({super.key, this.size = 48.0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const VIPMembershipScreen(),
          ),
        );
      },
      child: Container(
        height: size,
        width: size,
        alignment: Alignment.center,
        child: Text(
          '👑',
          style: TextStyle(
            fontSize: size * 0.6,
            shadows: [
              Shadow(
                color: Colors.amber.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
