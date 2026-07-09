import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../home/dashboard.dart';
import 'welcome_carousel.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _isLoading = false;

  final List<Map<String, dynamic>> _permissions = [
    {
      'title': 'Location',
      'description': 'To find the best clubs and venues near you, and verify check-ins.',
      'icon': Icons.location_on_rounded,
      'permission': Permission.location,
    },
    {
      'title': 'Notifications',
      'description': 'To keep you updated on party invites, booking statuses, and matches.',
      'icon': Icons.notifications_active_rounded,
      'permission': Permission.notification,
    },
    {
      'title': 'Storage & Photos',
      'description': 'To let you upload profile pictures, party photos, and venue images.',
      'icon': Icons.photo_library_rounded,
      'permission': Permission.photos,
    },
    {
      'title': 'Camera',
      'description': 'To scan QR codes and capture real-time moments for your plan hub.',
      'icon': Icons.camera_alt_rounded,
      'permission': Permission.camera,
    },
  ];

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    for (var item in _permissions) {
      Permission p = item['permission'];
      
      // Request one by one
      final status = await p.request();
      
      // For storage on newer Androids, we might also want to check Permission.storage
      if (p == Permission.photos && !status.isGranted) {
        await Permission.storage.request();
      }
    }

    // Save flag so we don't show this again unnecessarily
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_permissions_screen', true);

    if (mounted) {
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
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const WelcomeCarousel(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Header Image or Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.security_rounded,
                size: 64,
                color: LunaraTheme.electricViolet,
              ),
            ),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'ENHANCE YOUR EXPERIENCE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Lunara needs a few permissions to provide you with the best nightlife matching and booking experience.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _permissions.length,
                itemBuilder: (context, index) {
                  final p = _permissions[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Icon(
                            p['icon'],
                            color: LunaraTheme.electricViolet,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['title'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p['description'],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // Buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _requestPermissions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading 
                        ? const SizedBox(
                            width: 24, 
                            height: 24, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          )
                        : const Text(
                            'ALLOW ACCESS',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading ? null : () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('has_seen_permissions_screen', true);
                      _navigateToNext();
                    },
                    child: Text(
                      'SKIP FOR NOW',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
