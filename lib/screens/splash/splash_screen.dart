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
  static const String _prefKeyLastSplashVideoTime = 'last_splash_video_time';
  static const String _prefKeyLastSplashVideoDate = 'last_splash_video_date';
  static const int _minHoursBetweenVideo = 18;

  VideoPlayerController? _controller;
  bool _isInit = false;
  bool _isApiInitDone = false;
  bool _hasNavigated = false;
  bool _shouldPlayVideo = true;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastTimeMs = prefs.getInt(_prefKeyLastSplashVideoTime);
    final lastDateStr = prefs.getString(_prefKeyLastSplashVideoDate);

    bool playVideo = false;
    if (lastTimeMs == null || lastDateStr == null) {
      // First launch ever
      playVideo = true;
    } else {
      final lastTime = DateTime.fromMillisecondsSinceEpoch(lastTimeMs);
      final difference = now.difference(lastTime);
      final isNewDay = lastDateStr != todayStr;

      if (isNewDay || difference.inHours >= _minHoursBetweenVideo) {
        playVideo = true;
      }
    }

    _shouldPlayVideo = playVideo;

    if (playVideo) {
      // Record that we showed the video splash
      await prefs.setInt(_prefKeyLastSplashVideoTime, now.millisecondsSinceEpoch);
      await prefs.setString(_prefKeyLastSplashVideoDate, todayStr);

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
        _controller!.initialize().then((_) {
          if (mounted) {
            _controller!.setVolume(0.0); // Mute to allow autoplay on Web
            setState(() {
              _isInit = true;
            });
            _controller!.play();
            _controller!.addListener(_videoListener);
          }
        }).catchError((error) {
          debugPrint('Error initializing splash video: $error');
          _checkAndNavigate(force: true);
        }),
        _initAuthAndPush(),
      ]);
    } else {
      // Fast start (app restarted / already shown today)
      if (mounted) {
        setState(() {
          _isInit = true;
        });
      }

      await Future.wait([
        _initAuthAndPush(),
        Future.delayed(const Duration(milliseconds: 350)),
      ]);

      _checkAndNavigate(force: true);
    }
  }

  Future<void> _initAuthAndPush() async {
    try {
      await ApiService.initAuthToken();
      _isApiInitDone = true;
      if (ApiService.currentUserId != null) {
        PushNotificationService.initialize();
      }
      if (_shouldPlayVideo) {
        _checkAndNavigate();
      }
    } catch (error) {
      debugPrint('Error in initAuthToken: $error');
      _isApiInitDone = true;
      if (_shouldPlayVideo) {
        _checkAndNavigate();
      }
    }
  }

  void _videoListener() {
    if (_controller != null &&
        _controller!.value.isInitialized &&
        _controller!.value.position >= _controller!.value.duration) {
      _checkAndNavigate();
    }
  }

  void _checkAndNavigate({bool force = false}) {
    if (_hasNavigated) return;

    if (force ||
        (!_shouldPlayVideo && _isApiInitDone) ||
        (_isApiInitDone &&
            _controller != null &&
            _controller!.value.isInitialized &&
            _controller!.value.position >= _controller!.value.duration)) {
      _hasNavigated = true;
      _controller?.removeListener(_videoListener);
      _navigateToNext();
    }
  }

  void _navigateToNext() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final hasSeenPermissions =
        prefs.getBool('has_seen_permissions_screen') ?? false;

    if (!mounted) return;

    if (!hasSeenPermissions) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const PermissionsScreen(),
          transitionsBuilder: (_, a, _, child) =>
              FadeTransition(opacity: a, child: child),
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
          transitionsBuilder: (_, a, _, child) =>
              FadeTransition(opacity: a, child: child),
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
          transitionsBuilder: (_, a, _, child) =>
              FadeTransition(opacity: a, child: child),
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
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldPlayVideo &&
        _controller != null &&
        _isInit &&
        _controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
      );
    }

    // Branded static splash shown on fast restarts
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image.asset(
          'assets/images/logo_vertical_dark.png',
          width: 180,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Image.asset(
            'assets/images/lunara_logo.png',
            width: 180,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              'LUNARA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
