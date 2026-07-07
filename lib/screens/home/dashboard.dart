import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
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
  Timer? _badgeTimer;
  int _liveFeedCount = 0;
  int _chatCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _fetchBadges();
    _badgeTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchBadges(),
    );
  }

  Future<void> _fetchBadges() async {
    final counts = await ApiService.fetchBadgeCounts();
    if (mounted) {
      setState(() {
        _liveFeedCount = counts['liveFeedCount'] ?? 0;
        _chatCount = counts['chatCount'] ?? 0;
      });
      final total = counts['totalCount'] ?? 0;
      try {
        if (!kIsWeb && await FlutterAppBadger.isAppBadgeSupported()) {
          if (total > 0) {
            FlutterAppBadger.updateBadgeCount(total);
          } else {
            FlutterAppBadger.removeBadge();
          }
        }
      } catch (e) {
        debugPrint('FlutterAppBadger error: $e');
      }
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
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
    const LiveFeedScreen(isTab: true),
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
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
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
            icon: Badge(
              isLabelVisible: _liveFeedCount > 0,
              label: Text(
                _liveFeedCount > 99 ? '99+' : _liveFeedCount.toString(),
              ),
              child: Icon(
                Icons.favorite_outline,
                key: AppTourService.matchesTabKey,
              ),
            ),
            activeIcon: Badge(
              isLabelVisible: _liveFeedCount > 0,
              label: Text(
                _liveFeedCount > 99 ? '99+' : _liveFeedCount.toString(),
              ),
              child: const Icon(Icons.favorite),
            ),
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
            icon: Badge(
              isLabelVisible: _chatCount > 0,
              label: Text(_chatCount > 99 ? '99+' : _chatCount.toString()),
              child: Icon(
                Icons.chat_bubble_outline,
                key: AppTourService.messagesTabKey,
              ),
            ),
            activeIcon: Badge(
              isLabelVisible: _chatCount > 0,
              label: Text(_chatCount > 99 ? '99+' : _chatCount.toString()),
              child: const Icon(Icons.chat_bubble),
            ),
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
