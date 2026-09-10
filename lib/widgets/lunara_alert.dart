import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/notification_navigator.dart';

enum LunaraAlertSeverity {
  info,
  success,
  warning,
  error,
}

/// Centralized presentation layer for Lunara alerts, warnings, and toasts.
/// Guarantees that alerts NEVER render behind bottom sheets, modals, keyboards, or drawers.
class LunaraAlert {
  static OverlayEntry? _activeToastEntry;
  static Timer? _toastTimer;
  static bool _isModalActive = false;

  /// Returns the top-most OverlayState available in the app.
  static OverlayState? _resolveOverlay(BuildContext? context) {
    if (context != null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay != null) return overlay;
    }
    return NotificationNavigator.navigatorKey.currentState?.overlay;
  }

  /// Show a non-blocking floating foreground toast banner at the top of the screen.
  /// Always rendered on the root overlay so it floats above all modals and bottom sheets.
  static void showToast({
    BuildContext? context,
    required String message,
    String? title,
    LunaraAlertSeverity severity = LunaraAlertSeverity.info,
    Duration duration = const Duration(seconds: 4),
    IconData? icon,
    VoidCallback? onTap,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = _resolveOverlay(context);
      if (overlay == null) return;

      // Cancel previous toast cleanly
      dismissToast();

      final iconData = icon ?? _defaultIconForSeverity(severity);
      final colors = _colorsForSeverity(severity);

      _activeToastEntry = OverlayEntry(
        builder: (ctx) => _TopToastWidget(
          title: title,
          message: message,
          icon: iconData,
          gradientColors: colors.gradient,
          accentColor: colors.accent,
          duration: duration,
          onTap: onTap,
          onDismiss: dismissToast,
        ),
      );

      overlay.insert(_activeToastEntry!);

      _toastTimer = Timer(duration, () {
        dismissToast();
      });
    });
  }

  /// Dismiss active toast banner if present.
  static void dismissToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    try {
      _activeToastEntry?.remove();
    } catch (_) {}
    _activeToastEntry = null;
  }

  /// Show a blocking modal dialog in the foreground with dimmed backdrop.
  /// Guaranteed to render in front of any active bottom sheet, dialog, or keyboard.
  static Future<bool?> showModal({
    BuildContext? context,
    required String title,
    required String message,
    LunaraAlertSeverity severity = LunaraAlertSeverity.warning,
    String primaryButtonText = 'OK',
    VoidCallback? onPrimaryPressed,
    String? secondaryButtonText,
    VoidCallback? onSecondaryPressed,
    IconData? icon,
    bool barrierDismissible = true,
  }) async {
    final navContext = context ?? NotificationNavigator.navigatorKey.currentContext;
    if (navContext == null) return false;

    // Prevent multiple modal dialogs from stacking blindly
    if (_isModalActive) return false;
    _isModalActive = true;

    final iconData = icon ?? _defaultIconForSeverity(severity);
    final colors = _colorsForSeverity(severity);

    try {
      return await showGeneralDialog<bool>(
        context: navContext,
        useRootNavigator: true, // Guarantees rendering on the root navigation stack!
        barrierDismissible: barrierDismissible,
        barrierLabel: 'LunaraAlertModal',
        barrierColor: Colors.black.withValues(alpha: 0.65),
        transitionDuration: const Duration(milliseconds: 250),
        transitionBuilder: (ctx, anim1, anim2, child) {
          final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
          return ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: FadeTransition(
              opacity: anim1,
              child: child,
            ),
          );
        },
        pageBuilder: (ctx, anim1, anim2) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return SafeArea(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(ctx).size.width * 0.86,
                  constraints: const BoxConstraints(maxWidth: 380),
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status Icon Circle
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: colors.gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.accent.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          iconData,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Title
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'AllroundGothic',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Message
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        children: [
                          if (secondaryButtonText != null) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(ctx, rootNavigator: true).pop(false);
                                  onSecondaryPressed?.call();
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  side: BorderSide(
                                    color: isDark ? Colors.white24 : Colors.grey[300]!,
                                  ),
                                ),
                                child: Text(
                                  secondaryButtonText,
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(ctx, rootNavigator: true).pop(true);
                                onPrimaryPressed?.call();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.accent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                primaryButtonText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _isModalActive = false;
    }
  }

  // Convenience helper methods
  static void showWarningToast(String message, {BuildContext? context, String? title}) {
    showToast(
      context: context,
      message: message,
      title: title,
      severity: LunaraAlertSeverity.warning,
    );
  }

  static void showErrorToast(String message, {BuildContext? context, String? title}) {
    showToast(
      context: context,
      message: message,
      title: title,
      severity: LunaraAlertSeverity.error,
    );
  }

  static void showSuccessToast(String message, {BuildContext? context, String? title}) {
    showToast(
      context: context,
      message: message,
      title: title,
      severity: LunaraAlertSeverity.success,
    );
  }

  static Future<bool?> showErrorModal({
    BuildContext? context,
    required String title,
    required String message,
    String primaryButtonText = 'Understood',
    VoidCallback? onPrimaryPressed,
  }) {
    return showModal(
      context: context,
      title: title,
      message: message,
      severity: LunaraAlertSeverity.error,
      primaryButtonText: primaryButtonText,
      onPrimaryPressed: onPrimaryPressed,
    );
  }

  static Future<bool?> showWarningModal({
    BuildContext? context,
    required String title,
    required String message,
    String primaryButtonText = 'OK',
    String? secondaryButtonText,
    VoidCallback? onPrimaryPressed,
    VoidCallback? onSecondaryPressed,
  }) {
    return showModal(
      context: context,
      title: title,
      message: message,
      severity: LunaraAlertSeverity.warning,
      primaryButtonText: primaryButtonText,
      secondaryButtonText: secondaryButtonText,
      onPrimaryPressed: onPrimaryPressed,
      onSecondaryPressed: onSecondaryPressed,
    );
  }

  static IconData _defaultIconForSeverity(LunaraAlertSeverity severity) {
    switch (severity) {
      case LunaraAlertSeverity.success:
        return Icons.check_circle_rounded;
      case LunaraAlertSeverity.warning:
        return Icons.warning_amber_rounded;
      case LunaraAlertSeverity.error:
        return Icons.error_outline_rounded;
      case LunaraAlertSeverity.info:
        return Icons.info_outline_rounded;
    }
  }

  static ({List<Color> gradient, Color accent}) _colorsForSeverity(LunaraAlertSeverity severity) {
    switch (severity) {
      case LunaraAlertSeverity.success:
        return (
          gradient: [const Color(0xFF10B981), const Color(0xFF059669)],
          accent: const Color(0xFF10B981),
        );
      case LunaraAlertSeverity.warning:
        return (
          gradient: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
          accent: const Color(0xFFF59E0B),
        );
      case LunaraAlertSeverity.error:
        return (
          gradient: [const Color(0xFFEF4444), const Color(0xFFDC2626)],
          accent: const Color(0xFFEF4444),
        );
      case LunaraAlertSeverity.info:
        return (
          gradient: [LunaraTheme.electricViolet, const Color(0xFF6D28D9)],
          accent: LunaraTheme.electricViolet,
        );
    }
  }
}

class _TopToastWidget extends StatefulWidget {
  final String? title;
  final String message;
  final IconData icon;
  final List<Color> gradientColors;
  final Color accentColor;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    this.title,
    required this.message,
    required this.icon,
    required this.gradientColors,
    required this.accentColor,
    required this.duration,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismissWithAnimation() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: mediaQuery.padding.top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                widget.onTap?.call();
                _dismissWithAnimation();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: widget.accentColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: widget.gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.title != null) ...[
                            Text(
                              widget.title!,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            widget.message,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: isDark ? Colors.white54 : Colors.black45,
                      onPressed: _dismissWithAnimation,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
