import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/api_service.dart';
import '../../services/push_notification_service.dart';
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
      }),
      ApiService.initAuthToken().then((_) {
        _isApiInitDone = true;
        // Initialize push notifications after auth token is available
        if (ApiService.currentUserId != null) {
          PushNotificationService.initialize();
        }
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

  void _checkAndNavigate() {
    if (_hasNavigated) return;
    
    if (_isApiInitDone && 
        _controller.value.isInitialized && 
        _controller.value.position >= _controller.value.duration) {
      
      _hasNavigated = true;
      _controller.removeListener(_videoListener);
      _navigateToNext();
    }
  }

  void _navigateToNext() {
    if (!mounted) return;
    
    if (ApiService.currentUserId != null) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const Dashboard(),
          transitionsBuilder: (_, a, _, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
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
