import 'package:flutter/material.dart';
import '../core/theme.dart';

class LunaraPulsingLogoButton extends StatefulWidget {
  final double size;
  final double iconPadding;
  final VoidCallback? onTap;
  final double borderWidth;
  final Key? containerKey;

  const LunaraPulsingLogoButton({
    super.key,
    this.size = 34,
    this.iconPadding = 5,
    this.onTap,
    this.borderWidth = 1.5,
    this.containerKey,
  });

  @override
  State<LunaraPulsingLogoButton> createState() =>
      _LunaraPulsingLogoButtonState();
}

class _LunaraPulsingLogoButtonState extends State<LunaraPulsingLogoButton>
    with TickerProviderStateMixin {
  late AnimationController _heartbeatController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _ambientGlowAnimation;

  late AnimationController _clickGlowController;
  late Animation<double> _clickGlowAnimation;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();

    // 1. Subtle rhythmic heartbeat animation (smooth, relaxed pacing)
    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.045,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.045,
          end: 0.995,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.995,
          end: 1.03,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.03,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 42, // Relaxed resting pause before next pulse
      ),
    ]).animate(_heartbeatController);

    _ambientGlowAnimation = Tween<double>(begin: 0.10, end: 0.28).animate(
      CurvedAnimation(
        parent: _heartbeatController,
        curve: Curves.easeInOutSine,
      ),
    );

    _heartbeatController.repeat();

    // 2. Click burst purple glow animation
    _clickGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _clickGlowAnimation = CurvedAnimation(
      parent: _clickGlowController,
      curve: Curves.easeOutQuart,
    );
  }

  @override
  void dispose() {
    _heartbeatController.dispose();
    _clickGlowController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _clickGlowController.forward(from: 0.0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_heartbeatController, _clickGlowController]),
      builder: (context, child) {
        final double currentScale = _isPressed ? 0.92 : _scaleAnimation.value;

        final double clickProgress = _clickGlowAnimation.value;
        final double clickAlpha = (1.0 - clickProgress).clamp(0.0, 1.0);
        final double clickBlur = 6.0 + (16.0 * clickProgress);
        final double clickSpread = 1.0 + (5.0 * clickProgress);

        return Transform.scale(
          scale: currentScale,
          child: GestureDetector(
            key: widget.containerKey,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: _handleTap,
            child: Container(
              height: widget.size,
              width: widget.size,
              padding: EdgeInsets.all(widget.iconPadding),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: LunaraTheme.electricViolet.withValues(
                    alpha: 0.25 + (0.45 * clickAlpha),
                  ),
                  width: widget.borderWidth,
                ),
                boxShadow: [
                  // Continuous ambient heartbeat glow
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(
                      alpha: _ambientGlowAnimation.value,
                    ),
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                  // Click burst vibrant purple glow
                  if (_clickGlowController.isAnimating || clickProgress > 0)
                    BoxShadow(
                      color: const Color(
                        0xFF7F00FF,
                      ).withValues(alpha: 0.7 * clickAlpha),
                      blurRadius: clickBlur,
                      spreadRadius: clickSpread,
                    ),
                ],
              ),
              child: Image.asset(LunaraTheme.logoIcon, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }
}
