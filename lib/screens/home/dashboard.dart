import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../profile/profile_hub_screen.dart';
import '../discovery/discovery_screen.dart';
import '../social/live_feed_screen.dart';
import '../social/messages_screen.dart';
import '../social/plan_hub_screen.dart';
import '../../services/app_tour_service.dart';
import '../../services/push_notification_service.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import '../social/match_success_dialog.dart';
import '../onboarding/permissions_screen.dart' show NotificationPermissionRequest;

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  int _currentIndex = 0;
  User? _currentUser;
  Timer? _badgeTimer;
  int _liveFeedCount = 0;
  int _chatCount = 0;

  bool _isInitialized = false;
  late final List<Widget> _screens;
  final GlobalKey<LiveFeedScreenState> _liveFeedKey = GlobalKey<LiveFeedScreenState>();

  @override
  void initState() {
    super.initState();
    _screens = [
      const DiscoveryScreen(),
      LiveFeedScreen(key: _liveFeedKey, isTab: true, onCountChanged: _onLiveFeedCountChanged),
      const SizedBox.shrink(), // Placeholder for center button
      const MessagesScreen(),
      const ProfileHubScreen(),
    ];
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    _badgeTimer = Timer.periodic(
      const Duration(seconds: 30), // chat count synced from server
      (_) => _fetchBadges(),
    );
    _initSocketListeners();
  }

  Future<void> _initApp() async {
    try {
      await Future.wait([_loadProfile(), _fetchBadges()]);
    } catch (e) {
      debugPrint('Error during dashboard initialization: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
    // Soft-ask for notifications after login if not already granted
    _maybeAskNotificationPermission();
  }

  /// Shows a friendly in-app notification permission prompt if the user hasn't
  /// granted notifications yet. Only shown once per session unless denied permanently.
  Future<void> _maybeAskNotificationPermission() async {
    if (!mounted) return;
    // Don't bother on web / unsupported platforms
    if (kIsWeb) return;

    // Wait a beat so the screen fully renders first
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // Check current status
    final status = await Permission.notification.status;
    if (status.isGranted) return; // Already have permission

    // Check if user permanently dismissed this session's soft ask
    final prefs = await SharedPreferences.getInstance();
    final dismissedAt = prefs.getInt('notif_soft_ask_dismissed_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Re-ask at most once per 24 hours
    if (now - dismissedAt < const Duration(hours: 24).inMilliseconds) return;

    if (!mounted) return;

    if (status.isPermanentlyDenied) {
      // Show settings redirect prompt instead
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => NotificationPermissionRequest(
          onAllow: () {
            Navigator.pop(context);
            openAppSettings();
          },
          onDismiss: () async {
            Navigator.pop(context);
            final p = await SharedPreferences.getInstance();
            await p.setInt('notif_soft_ask_dismissed_at', DateTime.now().millisecondsSinceEpoch);
          },
        ),
      );
      return;
    }

    // Show the soft ask bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotificationPermissionRequest(
        onAllow: () async {
          Navigator.pop(context);
          final result = await Permission.notification.request();
          if (result.isGranted) {
            // Register FCM token now that we have permission
            await PushNotificationService.registerTokenAfterLogin();
          }
        },
        onDismiss: () async {
          Navigator.pop(context);
          final p = await SharedPreferences.getInstance();
          await p.setInt('notif_soft_ask_dismissed_at', DateTime.now().millisecondsSinceEpoch);
        },
      ),
    );
  }

  /// Called by the LiveFeedScreen whenever the user views/marks notifications.
  /// Immediately zeroes the live-feed badge (local-first) so the red dot
  /// disappears without waiting for a server round-trip.
  void _onLiveFeedCountChanged() {
    if (_liveFeedKey.currentState != null && mounted) {
      setState(() {
        _liveFeedCount = _liveFeedKey.currentState!.totalUnreadCount;
      });
    } else {
      _fetchBadges();
    }
  }

  void _onLiveFeedRead() async {
    if (!mounted) return;
    _liveFeedKey.currentState?.refreshFeed();
    if (_liveFeedKey.currentState != null) {
      setState(() {
        _liveFeedCount = _liveFeedKey.currentState!.totalUnreadCount;
      });
    } else {
      _fetchBadges();
    }
  }

  Future<void> _fetchBadges() async {
    final counts = await ApiService.fetchBadgeCounts();
    if (mounted) {
      setState(() {
        _liveFeedCount = counts['liveFeedCount'] ?? 0;
        _chatCount = counts['chatCount'] ?? 0;
      });
      _updateAppBadge(counts['totalCount'] ?? 0);
    }
  }

  Future<void> _updateAppBadge(int total) async {
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

  @override
  void dispose() {
    _disposeSocketListeners();
    WidgetsBinding.instance.removeObserver(this);
    _badgeTimer?.cancel();
    super.dispose();
  }

  void _initSocketListeners() {
    ApiService.addSocketListener('new_match', _onNewMatchReceived);
  }

  void _disposeSocketListeners() {
    ApiService.removeSocketListener('new_match', _onNewMatchReceived);
  }

  void _onNewMatchReceived(dynamic data) {
    if (!mounted) return;
    try {
      final matchedUserRaw = data['matchedUser'];
      if (matchedUserRaw != null) {
        final matchedUserMap = {
          'id': matchedUserRaw['id'],
          'name':
              '${matchedUserRaw['firstName'] ?? ''} ${matchedUserRaw['lastName'] ?? ''}'
                  .trim()
                  .toUpperCase(),
          'image':
              matchedUserRaw['profileImageUrl'] ??
              'https://picsum.photos/400/600',
          'isAsset': false,
        };
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Match',
          transitionDuration: const Duration(milliseconds: 400),
          transitionBuilder: (context, anim1, anim2, child) {
            return FadeTransition(
              opacity: anim1,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                  CurvedAnimation(parent: anim1, curve: Curves.elasticOut),
                ),
                child: child,
              ),
            );
          },
          pageBuilder: (context, anim1, anim2) {
            return MatchSuccessDialog(matchedUser: matchedUserMap);
          },
        );
      }
    } catch (e) {
      debugPrint('Error showing global new match dialog: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No location check needed on app resume
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

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F001E),
        body: Center(
          child: CircularProgressIndicator(color: LunaraTheme.cyberCyan),
        ),
      );
    }
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
                pageBuilder: (_, _, _) => const PlanHubScreen(),
                transitionsBuilder: (_, anim, _, child) {
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
            if (index == 1) {
              _liveFeedKey.currentState?.refreshFeed();
            }
            setState(() => _currentIndex = index);
            if (index == 1) {
              _onLiveFeedRead();
            }
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
              child: Icon(
                Icons.favorite_outline,
                key: AppTourService.matchesTabKey,
              ),
            ),
            activeIcon: Badge(
              isLabelVisible: _liveFeedCount > 0,
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
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 28,
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
            icon: Icon(Icons.settings_outlined, key: AppTourService.profileTabKey),
            activeIcon: const Icon(Icons.settings),
            label: 'Settings',
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
