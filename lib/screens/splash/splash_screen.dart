import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/api_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../onboarding/permissions_screen.dart';
import '../onboarding/welcome_carousel.dart';
import '../home/dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _isInit = false;
  bool _isApiInitDone = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    _controller = VideoPlayerController.asset('assets/videos/splash.mp4');
    
    // Safety fallback: if video fails or takes too long, force navigation
    Future.delayed(const Duration(seconds: 4), () {
      if (!_hasNavigated) {
        debugPrint('Splash screen fallback triggered');
        _checkAndNavigate(force: true);
      }
    });

    // Run both video initialization and API auth in parallel
    Future.wait([
      _controller.initialize().then((_) {
        if (mounted) {
          _controller.setVolume(0.0); // Mute to allow autoplay on Web
          setState(() {
            _isInit = true;
          });
          _controller.play();
          _controller.addListener(_videoListener);
        }
      }).catchError((error) {
        debugPrint('Error initializing splash video: $error');
        _checkAndNavigate(force: true);
      }),
      ApiService.initAuthToken().then((_) {
        _isApiInitDone = true;
        if (ApiService.currentUserId != null) {
          PushNotificationService.initialize();
        }
        _checkAndNavigate();
      }).catchError((error) {
        debugPrint('Error in initAuthToken: $error');
        _isApiInitDone = true;
        _checkAndNavigate();
      }),
    ]);
  }

  void _videoListener() {
    if (_controller.value.isInitialized && 
        _controller.value.position >= _controller.value.duration) {
      _checkAndNavigate();
    }
  }

  void _checkAndNavigate({bool force = false}) {
    if (_hasNavigated) return;
    
    if (force || (_isApiInitDone && 
        _controller.value.isInitialized && 
        _controller.value.position >= _controller.value.duration)) {
      
      _hasNavigated = true;
      _controller.removeListener(_videoListener);
      _navigateToNext();
    }
  }

  void _navigateToNext() async {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    final hasSeenPermissions = prefs.getBool('has_seen_permissions_screen') ?? false;

    if (!mounted) return;

    if (!hasSeenPermissions) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const PermissionsScreen(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    // Check 1: Resume from saved onboarding step if user disconnected or closed app
    final savedOnboarding = await OnboardingService.getSavedProgress();
    if (!mounted) return;

    if (savedOnboarding != null) {
      final step = savedOnboarding['step'] as String;
      final data = savedOnboarding['data'] as Map<String, dynamic>;
      final resumeScreen = OnboardingService.getResumeScreen(step, data);

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => resumeScreen,
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    // Check 2: Keep user logged in if authentication token exists in storage
    if (ApiService.isLoggedIn || ApiService.currentUserId != null) {
      try {
        await ApiService.fetchProfile();
      } catch (e) {
        debugPrint('Error fetching profile in splash: $e');
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const Dashboard(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    // Fallback: If user is not logged in, redirect to Welcome / Registration
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const WelcomeCarousel(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInit 
        ? SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          )
        : const SizedBox.shrink(),
    );
  }
}
