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

        // Main content
        child,
      ],
    );
  }
}
