import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_navigator.dart';
import '../services/push_notification_service.dart';
import '../widgets/lunara_profile_image.dart';

class TopNotificationBanner {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    Map<String, dynamic>? senderData,
    IconData? iconData,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = NotificationNavigator.navigatorKey.currentContext;
      if (context == null) return;

      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;

      _dismissTimer?.cancel();
      try {
        _currentEntry?.remove();
      } catch (_) {}
      _currentEntry = null;

      _currentEntry = OverlayEntry(
        builder: (ctx) => _TopBannerWidget(
          title: title,
          body: body,
          data: data,
          senderData: senderData,
          iconData: iconData,
          onDismiss: () {
            _dismissTimer?.cancel();
            try {
              _currentEntry?.remove();
            } catch (_) {}
            _currentEntry = null;
          },
        ),
      );

      overlay.insert(_currentEntry!);

      _dismissTimer = Timer(const Duration(seconds: 4), () {
        try {
          _currentEntry?.remove();
        } catch (_) {}
        _currentEntry = null;
      });
    });
  }
}

class _TopBannerWidget extends StatefulWidget {
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? senderData;
  final IconData? iconData;
  final VoidCallback onDismiss;

  const _TopBannerWidget({
    required this.title,
    required this.body,
    this.data,
    this.senderData,
    this.iconData,
    required this.onDismiss,
  });

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding =
        mediaQuery.padding.top > 0 ? mediaQuery.padding.top + 8 : 16.0;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Dismissible(
            key: UniqueKey(),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismiss(),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {
                  _dismiss();
                  if (widget.data != null) {
                    PushNotificationService.navigateFromPayload(widget.data!);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (widget.senderData != null &&
                          widget.senderData!.isNotEmpty)
                        LunaraProfileImage(
                          userData: widget.senderData!,
                          radius: 22,
                          showGradientBorder: true,
                        )
                      else
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFFC084FC)],
                            ),
                          ),
                          child: Icon(
                            widget.iconData ??
                                Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Text(
                                  'Just now',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.body,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
