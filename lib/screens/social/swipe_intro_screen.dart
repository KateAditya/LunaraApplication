import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';

class SwipeIntroScreen extends StatelessWidget {
  const SwipeIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                _buildSwipeHint(
                  color: LunaraTheme.accentVivid,
                  text: 'SWIPE RIGHT TO VIBE',
                  desc: 'Connect with people you want to party with.',
                ),
                const SizedBox(height: 60),
                _buildSwipeHint(
                  color: LunaraTheme.primaryDeep,
                  text: 'SWIPE LEFT TO SKIP',
                  desc: "Not your scene? Move to the next person.",
                ),
                const Spacer(),
                LunaraActionButton(
                  text: 'GOT IT',
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeHint({
    required Color color,
    required String text,
    required String desc,
  }) {
    return Column(
      children: [
        Text(
          text,
          style: LunaraTheme.headingStyle.copyWith(
            color: color,
            fontSize: 18,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          desc,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }
}
