import 'package:flutter/material.dart';

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
          ),
        ),
        // Soft White/Lavender Overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.3),
                  Colors.white.withValues(alpha: 0.9),
                ],
                stops: const [0.0, 0.5, 1.0],
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
