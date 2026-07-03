import 'package:flutter/material.dart';
import '../core/theme.dart';

class BumbleSwipeController {
  void Function(bool liked)? _swipeCallback;
  void Function(bool likedFromRight, Widget backtrackWidget)? _backtrackCallback;

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
  final BumbleSwipeController? controller;

  const BumbleSwipeWidget({
    super.key,
    required this.currentWidget,
    this.nextWidget,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onSwipePrev,
    this.controller,
  });

  @override
  State<BumbleSwipeWidget> createState() => _BumbleSwipeWidgetState();
}

class _BumbleSwipeWidgetState extends State<BumbleSwipeWidget> with TickerProviderStateMixin {
  late AnimationController _swipeAnimationController;
  late AnimationController _backtrackAnimationController;

  double _dragX = 0.0;
  double _dragY = 0.0;
  double _dragAngle = 0.0;
  bool _isSwipeAnimating = false;

  // Backtrack state
  bool _isBacktracking = false;
  Widget? _backtrackWidget;
  double _backtrackX = 0.0;
  late Animation<double> _backtrackAnimation;

  @override
  void initState() {
    super.initState();

    _swipeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _backtrackAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Set up backtrack animation with a smooth springy/easeOut curve
    _backtrackAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _backtrackAnimationController,
        curve: Curves.easeOutBack,
      ),
    );

    _backtrackAnimation.addListener(() {
      if (_isBacktracking) {
        setState(() {
          final double screenWidth = MediaQuery.of(context).size.width;
          final double startOffset = _backtrackX > 0 ? screenWidth : -screenWidth;
          _backtrackX = startOffset * _backtrackAnimation.value;
        });
      }
    });

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
      _animateSwipe(true);
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

    final Animation<double> snapAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _swipeAnimationController, curve: Curves.easeOutCubic),
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
    final double targetAngle = liked ? 0.4 : -0.4;

    final Animation<double> swipeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _swipeAnimationController, curve: Curves.easeOut),
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
    if (_isSwipeAnimating || _isBacktracking) return;

    setState(() {
      _isBacktracking = true;
      _backtrackWidget = backtrackWidget;
      _backtrackX = likedFromRight ? 1.0 : -1.0; // dummy value to set sign
    });

    _backtrackAnimationController.reset();
    _backtrackAnimationController.forward().then((_) {
      _isBacktracking = false;
      _backtrackWidget = null;
      _backtrackX = 0.0;
      widget.onSwipePrev();
    });
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final double opacity = width > 0 ? (_dragX.abs() / (width * 0.25)).clamp(0.0, 1.0) : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Bottom card (displays next profile widget scaled down)
        if (widget.nextWidget != null && !_isBacktracking)
          Positioned.fill(
            child: Transform.scale(
              scale: 0.95 + (0.05 * opacity),
              child: Opacity(
                opacity: 0.6 + (0.4 * opacity),
                child: widget.nextWidget!,
              ),
            ),
          ),

        // 2. Top card (displays current profile widget with rotation/offset)
        if (!_isBacktracking)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _handleDragStart,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              child: Transform(
                transform: Matrix4.translationValues(_dragX, _dragY, 0.0)
                  ..rotateZ(_dragAngle),
                alignment: Alignment.center,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.currentWidget,
                    
                    // LIKE Stamp Overlay
                    if (_dragX > 15)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: 50,
                        child: Center(
                          child: Transform.rotate(
                            angle: -0.2,
                            child: Opacity(
                              opacity: opacity,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: LunaraTheme.cyberCyan, width: 5),
                                  color: Colors.black.withValues(alpha: 0.25),
                                  boxShadow: [
                                    BoxShadow(
                                      color: LunaraTheme.cyberCyan.withValues(alpha: 0.4),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: LunaraTheme.cyberCyan,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // NOPE Stamp Overlay
                    if (_dragX < -15)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 50,
                        child: Center(
                          child: Transform.rotate(
                            angle: 0.2,
                            child: Opacity(
                              opacity: opacity,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: LunaraTheme.hotPink, width: 5),
                                  color: Colors.black.withValues(alpha: 0.25),
                                  boxShadow: [
                                    BoxShadow(
                                      color: LunaraTheme.hotPink.withValues(alpha: 0.4),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: LunaraTheme.hotPink,
                                  size: 48,
                                ),
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
          // Render a static copy of the current card underneath during backtrack
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: widget.currentWidget,
            ),
          ),

        // 3. Backtracking card (slides back on top from off-screen)
        if (_isBacktracking && _backtrackWidget != null)
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(_backtrackX, 0.0),
              child: Transform.rotate(
                angle: (_backtrackX / width) * 0.25,
                alignment: Alignment.center,
                child: _backtrackWidget!,
              ),
            ),
          ),
      ],
    );
  }
}
