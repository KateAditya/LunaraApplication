import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';

class ResetSuccessScreen extends StatelessWidget {
  const ResetSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              _buildSuccessAnimation(),
              const SizedBox(height: 48),
              const Text(
                'PASSWORD RESET',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 4,
                  color: LunaraTheme.electricViolet,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'ACCESS RESTORED',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your security credentials have been updated successfully. You can now return to the night.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
              const Spacer(),
              LunaraActionButton(
                text: 'BACK TO LOGIN',
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessAnimation() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer Glow
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: LunaraTheme.accentVivid.withValues(alpha: 0.1),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
        ),
        // Inner Circle
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: LunaraTheme.accentVivid, width: 2),
            gradient: RadialGradient(
              colors: [
                LunaraTheme.accentVivid.withValues(alpha: 0.2),
                Colors.transparent,
              ],
            ),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: LunaraTheme.accentVivid,
            size: 50,
          ),
        ),
      ],
    );
  }
}
