import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'dart:math' as math;

class AnimatedLogoWidget extends StatefulWidget {
  const AnimatedLogoWidget({super.key});

  @override
  State<AnimatedLogoWidget> createState() => _AnimatedLogoWidgetState();
}

class _AnimatedLogoWidgetState extends State<AnimatedLogoWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _arrow1Offset;
  late Animation<Offset> _arrow2Offset;
  late Animation<double> _arrowsOpacity;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));

    _arrow1Offset = Tween<Offset>(begin: const Offset(-2.0, -2.0), end: const Offset(0.2, 0.2)).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack)),
    );

    _arrow2Offset = Tween<Offset>(begin: const Offset(2.0, 2.0), end: const Offset(-0.2, -0.2)).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack)),
    );

    _arrowsOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.6, curve: Curves.easeOut)),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.7, curve: Curves.easeIn)),
    );

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.9, curve: Curves.elasticOut)),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      width: 120,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Final Logo
              Opacity(
                opacity: _logoOpacity.value,
                child: Transform.scale(
                  scale: _logoScale.value,
                  child: Hero(
                    tag: 'lunara_logo',
                    child: Image.asset(
                      LunaraTheme.logoIcon,
                      height: 120,
                      errorBuilder: (_, __, ___) => Container(
                        height: 90,
                        width: 90,
                        decoration: const BoxDecoration(
                          gradient: LunaraTheme.purpleGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            'L',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Arrow 1 (Top Left coming down)
              if (_controller.value < 0.6)
                Opacity(
                  opacity: _arrowsOpacity.value,
                  child: FractionalTranslation(
                    translation: _arrow1Offset.value,
                    child: Transform.rotate(
                      angle: math.pi / 4, // 45 degrees
                      child: const Icon(Icons.arrow_forward_ios_rounded, size: 60, color: LunaraTheme.electricViolet),
                    ),
                  ),
                ),

              // Arrow 2 (Bottom Right coming up)
              if (_controller.value < 0.6)
                Opacity(
                  opacity: _arrowsOpacity.value,
                  child: FractionalTranslation(
                    translation: _arrow2Offset.value,
                    child: Transform.rotate(
                      angle: math.pi * 1.25, // 225 degrees
                      child: const Icon(Icons.arrow_forward_ios_rounded, size: 60, color: LunaraTheme.electricViolet),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
