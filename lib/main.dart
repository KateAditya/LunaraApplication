import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'core/theme_manager.dart';
import 'screens/onboarding/permissions_screen.dart';
import 'screens/onboarding/welcome_carousel.dart';
import 'screens/home/dashboard.dart';
import 'services/onboarding_service.dart';
import 'services/notification_navigator.dart';
import 'services/push_notification_service.dart';
import 'services/biometric_service.dart';
import 'services/api_service.dart';
import 'firebase_options.dart';

import 'services/subscription_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the background message handler (must be top-level function)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Fast initialization without showing splash screen
  await ApiService.initAuthToken();
  if (ApiService.currentUserId != null) {
    PushNotificationService.initialize();
  }

  final prefs = await SharedPreferences.getInstance();
  final hasSeenPermissions =
      prefs.getBool('has_seen_permissions_screen') ?? false;

  Widget initialScreen;
  if (!hasSeenPermissions) {
    initialScreen = const PermissionsScreen();
  } else {
    final savedOnboarding = await OnboardingService.getSavedProgress();
    if (savedOnboarding != null) {
      final step = savedOnboarding['step'] as String;
      final data = savedOnboarding['data'] as Map<String, dynamic>;
      initialScreen = OnboardingService.getResumeScreen(step, data);
    } else if (ApiService.isLoggedIn || ApiService.currentUserId != null) {
      ApiService.fetchProfile().catchError((e) {
        debugPrint('Error fetching profile in background: $e');
        return null;
      });
      initialScreen = const Dashboard();
    } else {
      initialScreen = const WelcomeCarousel();
    }
  }

  runApp(LunaraApp(initialScreen: initialScreen));
}

class LunaraApp extends StatelessWidget {
  final Widget initialScreen;
  const LunaraApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeManager,
      builder: (context, _) {
        return MaterialApp(
          title: 'Lunara',
          debugShowCheckedModeBanner: false,
          theme: LunaraTheme.lightTheme,
          darkTheme: LunaraTheme.darkTheme,
          themeMode: themeManager.themeMode,
          navigatorKey: NotificationNavigator.navigatorKey,
          home: initialScreen,
          builder: (context, child) {
            return SubscriptionScope(
              child: AppLockWrapper(child: child ?? const SizedBox.shrink()),
            );
          },
        );
      },
    );
  }
}

class AppLockWrapper extends StatefulWidget {
  final Widget child;
  const AppLockWrapper({super.key, required this.child});

  static bool ignoreNextPause = false;

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper> with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (AppLockWrapper.ignoreNextPause) {
        AppLockWrapper.ignoreNextPause = false;
        return;
      }
      _lockApp();
    } else if (state == AppLifecycleState.resumed) {
      _promptAuthentication();
    }
  }

  Future<void> _checkInitialLock() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final hasToken = prefs.getString('auth_token') != null;

    if (biometricEnabled && hasToken) {
      setState(() {
        _isLocked = true;
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        _promptAuthentication();
      });
    }
  }

  void _lockApp() async {
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final hasToken = prefs.getString('auth_token') != null;

    if (biometricEnabled && hasToken) {
      setState(() {
        _isLocked = true;
      });
    }
  }

  Future<void> _promptAuthentication() async {
    if (!_isLocked || _authenticating) return;

    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final hasToken = prefs.getString('auth_token') != null;

    if (!biometricEnabled || !hasToken) {
      setState(() {
        _isLocked = false;
      });
      return;
    }

    _authenticating = true;
    try {
      final success = await BiometricService.authenticate(
        reason: 'Unlock Lunara to continue',
      );
      if (success && mounted) {
        setState(() {
          _isLocked = false;
        });
      }
    } finally {
      _authenticating = false;
    }
  }

  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F081D),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7F00FF).withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00B5FF).withValues(alpha: 0.1),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1F1235),
                        border: Border.all(
                          color: const Color(0xFF7F00FF),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7F00FF).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.lock_outline,
                          size: 55,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      "Lunara is Locked",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Verify your identity to access the app",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7F00FF),
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shadowColor: const Color(0xFF7F00FF).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _promptAuthentication,
                        icon: const Icon(Icons.fingerprint, size: 24),
                        label: const Text(
                          "UNLOCK APP",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('auth_token');
                        await ApiService.initAuthToken();
                        setState(() {
                          _isLocked = false;
                        });
                        final nav = NotificationNavigator.navigator;
                        if (nav != null) {
                          nav.pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const WelcomeCarousel()),
                            (route) => false,
                          );
                        }
                      },
                      child: const Text(
                        "Switch Account or Log Out",
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          ignoring: _isLocked,
          child: widget.child,
        ),
        if (_isLocked) _buildLockScreen(),
      ],
    );
  }
}
