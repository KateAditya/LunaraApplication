import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
    _initAndNavigate();
  }

  Future<void> _initAndNavigate() async {
    try {
      await ApiService.initAuthToken();
      if (ApiService.currentUserId != null) {
        PushNotificationService.initialize();
      }
    } catch (_) {}

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final hasSeenPermissions =
        prefs.getBool('has_seen_permissions_screen') ?? false;

    if (!mounted) return;

    if (!hasSeenPermissions) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionsScreen()),
      );
      return;
    }

    final savedOnboarding = await OnboardingService.getSavedProgress();
    if (!mounted) return;

    if (savedOnboarding != null) {
      final step = savedOnboarding['step'] as String;
      final data = savedOnboarding['data'] as Map<String, dynamic>;
      final resumeScreen = OnboardingService.getResumeScreen(step, data);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => resumeScreen),
      );
      return;
    }

    if (ApiService.isLoggedIn || ApiService.currentUserId != null) {
      ApiService.fetchProfile().catchError((e) {
        debugPrint('Error fetching profile in splash: $e');
        return null;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Dashboard()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeCarousel()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}
