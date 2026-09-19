import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A 3D Cube Page Route Transition
/// Creates a 3D cube face rotation when pushing or popping (backtracking) routes.
class CubePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;

  CubePageRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 400),
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return CubeTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              child: child,
            );
          },
        );
}

class CubeTransition extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const CubeTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, _) {
        // Entering page (animation goes from 0.0 to 1.0)
        final double animValue = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ).value;

        // Exiting page (secondaryAnimation goes from 0.0 to 1.0)
        final double secAnimValue = CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ).value;

        // If this page is being pushed/popped
        if (secAnimValue > 0.0) {
          // Outgoing rotation (turning left like front face of a cube turning away)
          final double angle = -secAnimValue * (math.pi / 2.5);
          final double translation = -secAnimValue * MediaQuery.of(context).size.width;

          return Transform(
            transform: Matrix4.translationValues(translation, 0.0, 0.0)
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            alignment: Alignment.centerRight,
            child: Container(
              foregroundDecoration: BoxDecoration(
                color: Colors.black.withValues(alpha: secAnimValue * 0.35),
              ),
              child: child,
            ),
          );
        }

        if (animValue < 1.0) {
          // Incoming rotation (turning from right into view)
          final double angle = (1.0 - animValue) * (math.pi / 2.5);
          final double translation = (1.0 - animValue) * MediaQuery.of(context).size.width;

          return Transform(
            transform: Matrix4.translationValues(translation, 0.0, 0.0)
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            alignment: Alignment.centerLeft,
            child: Container(
              foregroundDecoration: BoxDecoration(
                color: Colors.black.withValues(alpha: (1.0 - animValue) * 0.35),
              ),
              child: child,
            ),
          );
        }

        return child;
      },
    );
  }
}
