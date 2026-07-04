import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../home/dashboard.dart';
import '../../widgets/action_button.dart';

class AppTourScreen extends StatefulWidget {
  const AppTourScreen({super.key});

  @override
  State<AppTourScreen> createState() => _AppTourScreenState();
}

class _AppTourScreenState extends State<AppTourScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'DISCOVER\nTHE BEST VENUES',
      'description':
          'Find top-rated clubs, lounges, and bars tailored to your vibe. Check out interior galleries and exclusive menus before you step out.',
      'icon': Icons.local_fire_department_rounded,
      'gradient': LunaraTheme.primaryGradient,
    },
    {
      'title': 'CONNECT WITH\nVIBE-MATES',
      'description':
          'Meet new people sharing your nightlife interests. Plan hangouts, send Stranger Meet Requests, and party together safely.',
      'icon': Icons.people_alt_rounded,
      'gradient': LunaraTheme.secondaryGradient,
    },
    {
      'title': 'HOST &\nJOIN PARTIES',
      'description':
          'Create your own Party Plans or join public events hosted by others. Keep track of your bookings and guest lists in one place.',
      'icon': Icons.celebration_rounded,
      'gradient': LunaraTheme.purpleGradient,
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _finishTour();
    }
  }

  void _finishTour() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Dashboard()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LunaraTheme.darkBackground,
      body: Stack(
        children: [
          // Background ambient elements
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    LunaraTheme.electricViolet.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    LunaraTheme.cyberCyan.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // PageView for slides
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return _buildSlide(_pages[index]);
                    },
                  ),
                ),

                // Bottom Navigation
                _buildBottomNavigation(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide(Map<String, dynamic> pageData) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Glowing Icon Container
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: pageData['gradient'] as Gradient,
              boxShadow: [
                BoxShadow(
                  color: (pageData['gradient'] as LinearGradient).colors.first
                      .withValues(alpha: 0.4),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                pageData['icon'] as IconData,
                size: 80,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 64),
          Text(
            pageData['title'] as String,
            textAlign: TextAlign.center,
            style: LunaraTheme.headingStyle.copyWith(
              color: Colors.white,
              fontSize: 32,
              height: 1.2,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            pageData['description'] as String,
            textAlign: TextAlign.center,
            style: LunaraTheme.bodyStyle.copyWith(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dots indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pages.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: _currentPage == index ? 24 : 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? LunaraTheme.cyberCyan
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 48),

          // Action Buttons
          Row(
            children: [
              TextButton(
                onPressed: _finishTour,
                child: const Text(
                  'SKIP',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              _currentPage == _pages.length - 1
                  ? Expanded(
                      flex: 2,
                      child: LunaraActionButton(
                        text: 'GET STARTED',
                        onPressed: _finishTour,
                      ),
                    )
                  : InkWell(
                      onTap: _onNext,
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: LunaraTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: LunaraTheme.premiumCardShadow,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'NEXT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
