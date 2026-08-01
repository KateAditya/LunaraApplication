import 'package:flutter/material.dart';
import '../core/theme.dart';

class WelcomeBackground extends StatelessWidget {
  final Widget child;
  final String? backgroundImage;

  const WelcomeBackground({
    super.key,
    required this.child,
    this.backgroundImage,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background Image (Dynamic with fallback)
        Positioned.fill(
          child: Image.asset(
            backgroundImage ?? 'assets/images/welcome_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              decoration: BoxDecoration(
                gradient: LunaraTheme.purpleGradient,
              ),
            ),
          ),
        ),

        // Main content
        child,
      ],
    );
  }
}
