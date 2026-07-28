import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../home/dashboard.dart';

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
      'title': 'Discover\nTop Venues',
      'description': 'Find top-rated clubs, lounges, and bars tailored to your vibe. Check out exclusive menus before you step out.',
      'icon': Icons.local_fire_department_rounded,
      'color': LunaraTheme.electricViolet,
    },
    {
      'title': 'Connect\nWith Mates',
      'description': 'Meet new people sharing your nightlife interests. Send meet requests, and party together safely.',
      'icon': Icons.people_alt_rounded,
      'color': LunaraTheme.cyberCyan,
    },
    {
      'title': 'Host &\nJoin Parties',
      'description': 'Create your own Party Plans or join public events hosted by others. Keep track of your guest lists in one place.',
      'icon': Icons.celebration_rounded,
      'color': LunaraTheme.hotPink,
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
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
      );
    } else {
      _finishTour();
    }
  }

  void _finishTour() {
    HapticFeedback.lightImpact();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Dashboard()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _pages[_currentPage]['color'] as Color;

    return Scaffold(
      backgroundColor: LunaraTheme.darkBackground,
      body: Stack(
        children: [
          // Animated Ambient Glow
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 0.8,
                  colors: [
                    currentColor.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Bar with Skip
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedOpacity(
                        opacity: _currentPage == _pages.length - 1 ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: TextButton(
                          onPressed: _currentPage == _pages.length - 1 ? null : _finishTour,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white60,
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Content
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                      HapticFeedback.selectionClick();
                    },
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return _buildSlide(_pages[index], index == _currentPage);
                    },
                  ),
                ),

                // Bottom Controls
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Page Indicators
                      Row(
                        children: List.generate(
                          _pages.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(right: 8),
                            height: 6,
                            width: _currentPage == index ? 24 : 6,
                            decoration: BoxDecoration(
                              color: _currentPage == index 
                                  ? currentColor 
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      
                      // Next / Start Button
                      GestureDetector(
                        onTap: _onNext,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: _currentPage == _pages.length - 1 ? 32 : 24, 
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: currentColor,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: currentColor.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_currentPage == _pages.length - 1)
                                const Text(
                                  'GET STARTED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              if (_currentPage == _pages.length - 1)
                                const SizedBox(width: 8),
                              const Icon(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide(Map<String, dynamic> pageData, bool isActive) {
    final color = pageData['color'] as Color;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          
          // Icon visual
          AnimatedScale(
            scale: isActive ? 1.0 : 0.8,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: isActive ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    pageData['icon'] as IconData,
                    size: 48,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 48),
          
          // Title
          AnimatedSlide(
            offset: isActive ? Offset.zero : const Offset(0, 0.2),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: isActive ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: Text(
                pageData['title'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Description
          AnimatedSlide(
            offset: isActive ? Offset.zero : const Offset(0, 0.2),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: isActive ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 700),
              child: Text(
                pageData['description'] as String,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
