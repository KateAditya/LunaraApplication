import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../home/dashboard.dart';
import 'welcome_carousel.dart';

/// Data model for each permission step.
class _PermStep {
  final String title;
  final String headline;
  final String description;
  final String rationalMsg;
  final IconData icon;
  final Color accent;
  final Color iconBg;
  final Permission permission;
  final String ctaLabel;
  final String skipLabel;

  const _PermStep({
    required this.title,
    required this.headline,
    required this.description,
    required this.rationalMsg,
    required this.icon,
    required this.accent,
    required this.iconBg,
    required this.permission,
    required this.ctaLabel,
    required this.skipLabel,
  });
}

const List<_PermStep> _steps = [
  _PermStep(
    title: 'Stay in the Loop',
    headline: 'Turn on\nNotifications',
    description:
        'Never miss a party invite, match, or booking update.\nWe\'ll send you only what matters - no spam, ever.',
    rationalMsg:
        'Lunara uses notifications to alert you of party invites, instant matches, booking confirmations, and messages from your plans.',
    icon: Icons.notifications_active_rounded,
    accent: Color(0xFF7F00FF),
    iconBg: Color(0x1A7F00FF),
    permission: Permission.notification,
    ctaLabel: 'Allow Notifications',
    skipLabel: 'Maybe Later',
  ),
  _PermStep(
    title: 'Find Venues Near You',
    headline: 'Enable\nLocation',
    description:
        'Discover the hottest clubs and venues right in your city.\nWe use your location to show hyper-local plans.',
    rationalMsg:
        'Lunara uses location to show you nearby venues, events, and party plans. Your location is never shared without your consent.',
    icon: Icons.location_on_rounded,
    accent: Color(0xFF00A9FF),
    iconBg: Color(0x1A00A9FF),
    permission: Permission.locationWhenInUse,
    ctaLabel: 'Allow Location',
    skipLabel: 'Not Now',
  ),
  _PermStep(
    title: 'Share Your Moments',
    headline: 'Access\nPhotos',
    description:
        'Upload your best photos for your profile and plan highlights.\nYour photos, your privacy — always in your control.',
    rationalMsg:
        'Lunara needs photo access so you can set your profile picture and upload party photos to your plan hub.',
    icon: Icons.photo_library_rounded,
    accent: Color(0xFFE100FF),
    iconBg: Color(0x1AE100FF),
    permission: Permission.photos,
    ctaLabel: 'Allow Photos',
    skipLabel: 'Skip for Now',
  ),
  _PermStep(
    title: 'Scan & Capture',
    headline: 'Use\nCamera',
    description:
        'Scan venue QR codes for instant check-in and capture\nmoments from your night out.',
    rationalMsg:
        'Camera access lets you scan QR codes for check-in and capture photos for your profile and plans.',
    icon: Icons.camera_alt_rounded,
    accent: Color(0xFF00E5FF),
    iconBg: Color(0x1A00E5FF),
    permission: Permission.camera,
    ctaLabel: 'Allow Camera',
    skipLabel: 'Skip',
  ),
];

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  bool _isRequesting = false;

  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _iconBounce;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _iconBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bounceAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.90), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.90, end: 1.00), weight: 30),
    ]).animate(CurvedAnimation(parent: _iconBounce, curve: Curves.easeInOut));

    _slideController.forward();
    _iconBounce.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pulseController.dispose();
    _iconBounce.dispose();
    super.dispose();
  }

  Future<void> _advance({bool skip = false}) async {
    if (_isRequesting) return;

    final step = _steps[_currentStep];

    if (!skip) {
      setState(() => _isRequesting = true);

      // Check current status first
      PermissionStatus status = await step.permission.status;

      if (status.isPermanentlyDenied) {
        // System dialog won't show — open app settings instead
        if (mounted) {
          await _showSettingsDialog(step);
        }
        setState(() => _isRequesting = false);
        return;
      }

      // Request the permission
      status = await step.permission.request();

      // For older Android: also request storage alongside photos
      if (step.permission == Permission.photos && !status.isGranted) {
        await Permission.storage.request();
      }

      setState(() => _isRequesting = false);
    }

    // Move to next step
    if (_currentStep < _steps.length - 1) {
      await _slideController.reverse();
      setState(() {
        _currentStep++;
        _iconBounce.reset();
      });
      _slideController.forward();
      _iconBounce.forward();
    } else {
      _finish();
    }
  }

  Future<void> _showSettingsDialog(_PermStep step) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: step.iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(step.icon, color: step.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${step.title} Permission',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '${step.rationalMsg}\n\nPlease tap "Open Settings" and allow the permission manually.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Not Now',
              style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: step.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _finish() async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_permissions_screen', true);
    if (!mounted) return;

    if (ApiService.currentUserId != null) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, a1, a2) => const Dashboard(),
          transitionsBuilder: (context, a, b, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, a1, a2) => const WelcomeCarousel(),
          transitionsBuilder: (context, a, b, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];
    final size = MediaQuery.of(context).size;
    final isLastStep = _currentStep == _steps.length - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // ── Progress Dots ─────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: List.generate(_steps.length, (i) {
                    final isActive = i == _currentStep;
                    final isPast = i < _currentStep;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 6),
                      height: 4,
                      width: isActive ? 28 : 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? step.accent
                            : isPast
                                ? step.accent.withValues(alpha: 0.35)
                                : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ),
              ),

              // ── Main Content ──────────────────────────────
              Expanded(
                child: SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Big animated permission icon
                          Center(
                            child: AnimatedBuilder(
                              animation: Listenable.merge([_pulseAnim, _bounceAnim]),
                              builder: (ctx, child2) => Transform.scale(
                                scale: _bounceAnim.value * (_isRequesting ? 1.0 : _pulseAnim.value),
                                child: Container(
                                  width: size.width * 0.38,
                                  height: size.width * 0.38,
                                  decoration: BoxDecoration(
                                    color: step.iconBg,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: step.accent.withValues(alpha: 0.22),
                                        blurRadius: 40,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      step.icon,
                                      size: size.width * 0.16,
                                      color: step.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 44),

                          // Step tag
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: step.accent.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              step.title.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                                color: step.accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Headline
                          Text(
                            step.headline,
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                              letterSpacing: -1,
                              color: Color(0xFF0F0F12),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Description
                          Text(
                            step.description,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Bottom Buttons ────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 0, 24, MediaQuery.of(context).padding.bottom + 20),
                child: Column(
                  children: [
                    // PRIMARY CTA
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, child) => Transform.scale(
                          scale: _isRequesting ? 1.0 : (1.0 + (_pulseAnim.value - 1.0) * 0.015),
                          child: child,
                        ),
                        child: ElevatedButton(
                          onPressed: _isRequesting ? null : () => _advance(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: step.accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                step.accent.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 0,
                            shadowColor: step.accent.withValues(alpha: 0.35),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _isRequesting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Row(
                                    key: ValueKey(_currentStep),
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        step.ctaLabel,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded,
                                          size: 18),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // SKIP / SECONDARY
                    TextButton(
                      onPressed: _isRequesting
                          ? null
                          : () => _advance(skip: true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[500],
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: Text(
                        isLastStep ? 'All done — Let\'s Go →' : step.skipLabel,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A lightweight helper widget shown as an in-app rational dialog
/// *before* the OS dialog. Used for soft-ask flows from inside the app.
class NotificationPermissionRequest extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onDismiss;

  const NotificationPermissionRequest({
    super.key,
    required this.onAllow,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0x1A7F00FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: LunaraTheme.electricViolet,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Don\'t miss a thing 🎉',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F0F12),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Allow Lunara to send you notifications\nfor party invites, matches, and booking\nconfirmations.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onAllow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Allow Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onDismiss,
              child: Text(
                'Not Now',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
