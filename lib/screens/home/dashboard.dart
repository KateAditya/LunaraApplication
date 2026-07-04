import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../profile/profile_hub_screen.dart';
import '../profile/vip_membership_screen.dart';
import '../discovery/discovery_screen.dart';
import '../social/live_feed_screen.dart';
import '../social/messages_screen.dart';
import '../social/plan_hub_screen.dart';
import '../../services/app_tour_service.dart';

import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _currentIndex = 0;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = await ApiService.fetchProfile();
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppTourService.showDashboardTour(context);
    });
  }

  final List<Widget> _screens = [
    const DiscoveryScreen(),
    const LiveFeedScreen(),
    const SizedBox.shrink(), // Placeholder for center button
    const MessagesScreen(),
    const ProfileHubScreen(),
  ];



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex == 2 ? 0 : _currentIndex,
            children: _screens,
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: AnimatedUpgradeButton(
              key: AppTourService.vipUpgradeKey,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const VIPMembershipScreen()));
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 2) {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const PlanHubScreen(),
                transitionsBuilder: (_, anim, __, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
                transitionDuration: const Duration(milliseconds: 350),
              ),
            );
          } else {
            setState(() => _currentIndex = index);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: LunaraTheme.electricViolet,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined, key: AppTourService.homeTabKey),
            activeIcon: const Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_outline, key: AppTourService.matchesTabKey),
            activeIcon: const Icon(Icons.favorite),
            label: 'Live Feed',
          ),
          BottomNavigationBarItem(
            icon: Container(
              key: AppTourService.postTabKey,
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                gradient: LunaraTheme.deepPurpleGradient,
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/images/logo_icon.png',
                width: 30,
                height: 30,
                color: Colors.white,
              ),
            ),
            label: 'Post',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline, key: AppTourService.messagesTabKey),
            activeIcon: const Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: _buildProfileIcon(false, key: AppTourService.profileTabKey),
            activeIcon: _buildProfileIcon(true),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildProfileIcon(bool isActive, {Key? key}) {
    return Container(
      key: key,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isActive 
          ? Border.all(color: LunaraTheme.electricViolet, width: 2)
          : Border.all(color: Colors.transparent, width: 2),
      ),
      child: Center(
        child: LunaraProfileImage(
          user: _currentUser,
          radius: 12,
          showGradientBorder: false,
          isInteractive: false,
        ),
      ),
    );
  }
}

class AnimatedUpgradeButton extends StatefulWidget {
  final VoidCallback onTap;
  
  const AnimatedUpgradeButton({super.key, required this.onTap});

  @override
  State<AnimatedUpgradeButton> createState() => _AnimatedUpgradeButtonState();
}

class _AnimatedUpgradeButtonState extends State<AnimatedUpgradeButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulseValue = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
          final scale = 1.0 + (0.08 * pulseValue);
          final glow = 4.0 + (11.0 * pulseValue);

          return Transform.scale(
            scale: scale,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C0055), Color(0xFF6B00B6)], // Premium deep purple
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.8), // Golden border
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.4), // Golden glow
                    blurRadius: glow,
                    spreadRadius: glow / 4,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // Softer perspective
                    ..rotateY(math.sin(_controller.value * 2 * math.pi) * 0.4), // Subtle 3D rocking
                  child: const Text(
                    '👑',
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
