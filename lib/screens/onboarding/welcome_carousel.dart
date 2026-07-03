import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/welcome_background.dart';
import '../auth/login_hub.dart';

class WelcomeCarousel extends StatefulWidget {
  const WelcomeCarousel({super.key});

  @override
  State<WelcomeCarousel> createState() => _WelcomeCarouselState();
}

class _WelcomeCarouselState extends State<WelcomeCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _slides = [
    {
      'tagline': 'UNLOCK THE NIGHT',
      'titlePart1': 'UNLOCK',
      'titlePart2': 'THE NIGHT',
      'subtitle': 'The ultimate platform to find and book your perfect partner for an unforgettable clubbing experience.',
      'bg': 'assets/images/welcome_bg.png',
    },
    {
      'tagline': 'CONNECT TOGETHER',
      'titlePart1': 'MATCH AND',
      'titlePart2': 'SOCIALIZE',
      'subtitle': 'Connect with like minded people who share your taste in music and nightlife vibe.',
      'bg': 'assets/images/welcome_bg_2.png',
    },
    {
      'tagline': 'VIP EXPERIENCE',
      'titlePart1': 'PREMIUM',
      'titlePart2': 'ACCESS',
      'subtitle': 'Book exclusive tables, join VIP guestlists, and split bills seamlessly with your night partner.',
      'bg': 'assets/images/welcome_bg_3.png',
    },
  ];

  void _handleNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginHub()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPage = index),
        itemCount: _slides.length,
        itemBuilder: (context, index) {
          final slide = _slides[index];
          return WelcomeBackground(
            backgroundImage: slide['bg'] ?? 'assets/images/welcome_bg.png',
            child: GestureDetector(
              onTap: _handleNext,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Expanded(
                    child: _buildSlide(slide),
                  ),
                  _buildControls(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlide(Map<String, String> slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 54), // Even more compact
      child: Column(
        children: [
          const SizedBox(height: 60),
          // Logo Section
          Image.asset(LunaraTheme.logoIcon, height: 200),
          const SizedBox(height: 10),
          Text(
            slide['tagline']?.toUpperCase() ?? 'UNLOCK THE NIGHT',
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 4,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(flex: 1), // Shift card down
          // Content Area (No card background)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_open_rounded, color: LunaraTheme.electricViolet, size: 28),
                ),
                const SizedBox(height: 24),
                // Title with split color
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'AllroundGothic',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      letterSpacing: 1,
                    ),
                    children: [
                      TextSpan(text: '${slide['titlePart1']} '),
                      TextSpan(
                        text: slide['titlePart2'],
                        style: const TextStyle(color: LunaraTheme.electricViolet),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  slide['subtitle'] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                    height: 1.4,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                // Bottom line indicator
                Container(
                  width: 30,
                  height: 2,
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Dot Indicators on the left
          Row(
            children: List.generate(_slides.length, (index) => Container(
              margin: const EdgeInsets.only(right: 6),
              height: 6,
              width: _currentPage == index ? 18 : 6,
              decoration: BoxDecoration(
                color: _currentPage == index ? LunaraTheme.electricViolet : Colors.grey[300],
                borderRadius: BorderRadius.circular(3),
              ),
            )),
          ),
          // Circular Button on the right
          GestureDetector(
            onTap: _handleNext,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LunaraTheme.purpleGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                _currentPage == _slides.length - 1 ? Icons.check : Icons.arrow_forward,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
