import 'dart:math' as math;
import 'package:flutter/material.dart';

class BumbleSwipeController {
  void Function(bool liked)? _swipeCallback;
  void Function(bool likedFromRight, Widget backtrackWidget)?
  _backtrackCallback;

  void swipe(bool liked) {
    _swipeCallback?.call(liked);
  }

  void backtrack(bool likedFromRight, Widget backtrackWidget) {
    _backtrackCallback?.call(likedFromRight, backtrackWidget);
  }
}

class BumbleSwipeWidget extends StatefulWidget {
  final Widget currentWidget;
  final Widget? nextWidget;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipePrev;
  final bool Function()? canSwipeRight;
  final BumbleSwipeController? controller;

  const BumbleSwipeWidget({
    super.key,
    required this.currentWidget,
    this.nextWidget,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onSwipePrev,
    this.canSwipeRight,
    this.controller,
  });

  @override
  State<BumbleSwipeWidget> createState() => _BumbleSwipeWidgetState();
}

class _BumbleSwipeWidgetState extends State<BumbleSwipeWidget>
    with TickerProviderStateMixin {
  late AnimationController _swipeAnimationController;
  late AnimationController _backtrackAnimationController;

  double _dragX = 0.0;
  double _dragY = 0.0;
  double _dragAngle = 0.0;
  bool _isSwipeAnimating = false;

  // Backtrack state
  bool _isBacktracking = false;
  bool _backtrackFromRight = false;
  Widget? _backtrackWidget;
  late Animation<double> _backtrackAnimation;

  @override
  void initState() {
    super.initState();

    _swipeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _backtrackAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );

    // Smooth cubic curve for 3D cube backtrack
    _backtrackAnimation = CurvedAnimation(
      parent: _backtrackAnimationController,
      curve: Curves.easeOutCubic,
    );

    if (widget.controller != null) {
      widget.controller!._swipeCallback = _performProgrammaticSwipe;
      widget.controller!._backtrackCallback = _performBacktrack;
    }
  }

  @override
  void didUpdateWidget(covariant BumbleSwipeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._swipeCallback = null;
      oldWidget.controller?._backtrackCallback = null;
      if (widget.controller != null) {
        widget.controller!._swipeCallback = _performProgrammaticSwipe;
        widget.controller!._backtrackCallback = _performBacktrack;
      }
    }
  }

  @override
  void dispose() {
    _swipeAnimationController.dispose();
    _backtrackAnimationController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (_isSwipeAnimating || _isBacktracking) return;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isSwipeAnimating || _isBacktracking) return;
    final double width = MediaQuery.of(context).size.width;
    if (width <= 0) return;

    setState(() {
      _dragX += details.delta.dx;
      _dragY += details.delta.dy;
      // Angle: rotate up to 15 degrees (~0.26 rad) at full screen drag
      _dragAngle = (_dragX / width) * 0.25;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isSwipeAnimating || _isBacktracking) return;

    final double width = MediaQuery.of(context).size.width;
    final double velocity = details.primaryVelocity ?? 0.0;
    const double velocityThreshold = 400.0;
    final double swipeThreshold = width * 0.35;

    if (_dragX > swipeThreshold || velocity > velocityThreshold) {
      if (widget.canSwipeRight != null && !widget.canSwipeRight!()) {
        _animateSnapBack();
        widget.onSwipeRight();
        return;
      }
      _isSwipeAnimating = false;
      setState(() {
        _dragX = 0.0;
        _dragY = 0.0;
        _dragAngle = 0.0;
      });
      widget.onSwipeRight();
    } else if (_dragX < -swipeThreshold || velocity < -velocityThreshold) {
      _animateSwipe(false);
    } else {
      _animateSnapBack();
    }
  }

  void _animateSnapBack() {
    final double startX = _dragX;
    final double startY = _dragY;
    final double startAngle = _dragAngle;

    final Animation<double> snapAnim = Tween<double>(begin: 1.0, end: 0.0)
        .animate(
          CurvedAnimation(
            parent: _swipeAnimationController,
            curve: Curves.easeOutCubic,
          ),
        );

    void listener() {
      setState(() {
        _dragX = startX * snapAnim.value;
        _dragY = startY * snapAnim.value;
        _dragAngle = startAngle * snapAnim.value;
      });
    }

    snapAnim.addListener(listener);

    _swipeAnimationController.reset();
    _swipeAnimationController.forward().then((_) {
      snapAnim.removeListener(listener);
    });
  }

  void _animateSwipe(bool liked) {
    _isSwipeAnimating = true;
    final double startX = _dragX;
    final double startY = _dragY;
    final double startAngle = _dragAngle;
    final double width = MediaQuery.of(context).size.width;
    final double targetX = liked ? width * 1.3 : -width * 1.3;
    final double targetAngle = liked ? 0.35 : -0.35;

    final Animation<double> swipeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(
          CurvedAnimation(
            parent: _swipeAnimationController,
            curve: Curves.easeOutCubic,
          ),
        );

    void listener() {
      setState(() {
        _dragX = startX + (targetX - startX) * swipeAnim.value;
        _dragY = startY * (1.0 - swipeAnim.value);
        _dragAngle = startAngle + (targetAngle - startAngle) * swipeAnim.value;
      });
    }

    swipeAnim.addListener(listener);

    _swipeAnimationController.reset();
    _swipeAnimationController.forward().then((_) {
      swipeAnim.removeListener(listener);
      _isSwipeAnimating = false;
      setState(() {
        _dragX = 0.0;
        _dragY = 0.0;
        _dragAngle = 0.0;
      });
      if (liked) {
        widget.onSwipeRight();
      } else {
        widget.onSwipeLeft();
      }
    });
  }

  void _performProgrammaticSwipe(bool liked) {
    if (_isSwipeAnimating || _isBacktracking) return;
    setState(() {
      _dragX = 0.0;
      _dragY = 0.0;
      _dragAngle = 0.0;
    });
    _animateSwipe(liked);
  }

  void _performBacktrack(bool likedFromRight, Widget backtrackWidget) {
    _swipeAnimationController.stop();
    _isSwipeAnimating = false;

    setState(() {
      _isBacktracking = true;
      _backtrackFromRight = likedFromRight;
      _backtrackWidget = backtrackWidget;
      _dragX = 0.0;
      _dragY = 0.0;
      _dragAngle = 0.0;
    });

    _backtrackAnimationController.reset();
    _backtrackAnimationController.forward().then((_) {
      if (mounted) {
        setState(() {
          _isBacktracking = false;
          _backtrackWidget = null;
        });
        widget.onSwipePrev();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final double dragRatio = width > 0 ? (_dragX / width).clamp(-1.0, 1.0) : 0.0;
    final double dragProgress = dragRatio.abs();

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // 1. Bottom card (displays next profile widget with subtle 3D depth and scale)
        if (widget.nextWidget != null && !_isBacktracking)
          Positioned.fill(
            child: Transform(
              transform: Matrix4.diagonal3Values(
                0.94 + (0.06 * dragProgress),
                0.94 + (0.06 * dragProgress),
                1.0,
              )
                ..setEntry(3, 2, 0.001)
                ..rotateY((_dragX > 0 ? -0.15 : 0.15) * (1.0 - dragProgress)),
              alignment: Alignment.center,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.nextWidget!,
                  // Subtle shadow overlay that fades out as the card comes to the foreground
                  IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(
                        alpha: (0.35 * (1.0 - dragProgress)).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 2. Top card (displays current profile widget with 3D cube rotation and translation)
        if (!_isBacktracking)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _handleDragStart,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              child: Transform(
                transform: Matrix4.translationValues(_dragX, _dragY, 0.0)
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(dragRatio * 0.28) // 3D Cube face tilt
                  ..rotateZ(_dragAngle),
                alignment: Alignment.center,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.currentWidget,
                    // BACKTRACK overlay hint when dragging right
                    if (_dragX > 30)
                      Positioned(
                        top: 50,
                        left: 20,
                        child: Transform.rotate(
                          angle: -0.2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFFB703), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFB703).withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.replay_rounded, color: Color(0xFFFFB703), size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'BACKTRACK',
                                  style: TextStyle(
                                    color: Color(0xFFFFB703),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // NOPE overlay hint when dragging left
                    if (_dragX < -30)
                      Positioned(
                        top: 50,
                        right: 20,
                        child: Transform.rotate(
                          angle: 0.2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFF3366), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF3366).withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Text(
                              'NOPE',
                              style: TextStyle(
                                color: Color(0xFFFF3366),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          )
        else
          // 3. During Backtrack: Render 3D Cube transition between current & incoming card
          AnimatedBuilder(
            animation: _backtrackAnimation,
            builder: (context, _) {
              final double t = _backtrackAnimation.value; // 0.0 -> 1.0
              final double screenW = width > 0 ? width : MediaQuery.of(context).size.width;

              // Direction of backtrack: if previous swipe was from left, backtrack comes in from left
              final double dir = _backtrackFromRight ? 1.0 : -1.0;

              // Outgoing current card (rotates out in 3D perspective)
              final double outgoingAngle = dir * t * (math.pi / 2.6);
              final double outgoingTranslate = -dir * t * screenW;

              // Incoming backtrack card (rotates in in 3D perspective)
              final double incomingAngle = -dir * (1.0 - t) * (math.pi / 2.6);
              final double incomingTranslate = dir * (1.0 - t) * screenW;

              return Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  // Outgoing face of cube
                  Transform(
                    transform: Matrix4.translationValues(outgoingTranslate, 0.0, 0.0)
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(outgoingAngle),
                    alignment: _backtrackFromRight ? Alignment.centerRight : Alignment.centerLeft,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.currentWidget,
                        IgnorePointer(
                          child: Container(
                            color: Colors.black.withValues(alpha: (t * 0.45).clamp(0.0, 1.0)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Incoming face of cube (Backtracking profile)
                  if (_backtrackWidget != null)
                    Transform(
                      transform: Matrix4.translationValues(incomingTranslate, 0.0, 0.0)
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(incomingAngle),
                      alignment: _backtrackFromRight ? Alignment.centerLeft : Alignment.centerRight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _backtrackWidget!,
                          IgnorePointer(
                            child: Container(
                              color: Colors.black.withValues(alpha: ((1.0 - t) * 0.45).clamp(0.0, 1.0)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

