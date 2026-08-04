import 'package:flutter/material.dart';

class ReliabilityBadge extends StatelessWidget {
  final int score;
  final bool showScoreText;

  const ReliabilityBadge({
    super.key,
    required this.score,
    this.showScoreText = false,
  });

  String get _ratingLabel {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 60) return 'Average';
    if (score >= 40) return 'Low';
    return 'Very Low';
  }

  Color get _badgeColor {
    if (score >= 90) return const Color(0xFF10B981); // Emerald Green
    if (score >= 75) return const Color(0xFF8B5CF6); // Purple
    if (score >= 60) return const Color(0xFFF59E0B); // Amber
    if (score >= 40) return const Color(0xFFF97316); // Orange
    return const Color(0xFFEF4444); // Red
  }

  IconData get _icon {
    if (score >= 75) return Icons.verified_user_rounded;
    if (score >= 60) return Icons.shield_rounded;
    return Icons.warning_amber_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _badgeColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 14, color: _badgeColor),
          const SizedBox(width: 5),
          Text(
            _ratingLabel,
            style: TextStyle(
              color: _badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          if (showScoreText) ...[
            const SizedBox(width: 4),
            Text(
              '($score)',
              style: TextStyle(
                color: _badgeColor.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
