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
      'tagline': 'Find your kind of people.',
      'titlePart1': '',
      'titlePart2': '',
      'subtitle': 'No forcing. No pretending.\nJust good company.',
      'bg': 'assets/images/welcome_bg.png',
    },
    {
      'tagline': 'Less texting. More showing up.',
      'titlePart1': '',
      'titlePart2': '',
      'subtitle':
          'Find people who actually want to grab coffee, hit a gig,\n or explore the city.',
      'bg': 'assets/images/welcome_bg_2.png',
    },
    {
      'tagline': 'Main Character Energy nights only.',
      'titlePart1': '',
      'titlePart2': '',
      'subtitle':
          'Exclusive perks, premium experiences, and plans worth\n cancelling your Netflix for.',
      'bg': 'assets/images/welcome_bg_3.png',
    },
  ];

  void _handleNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginHub()),
      );
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
                  Expanded(flex: 70, child: _buildSlide(slide, index)),
                  Expanded(flex: 15, child: _buildTextSection(slide, index)),
                  Expanded(flex: 15, child: _buildButtonSection()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlide(Map<String, String> slide, int index) {
    if (index == 0) {
      // The background image already contains the scattered pills graphic.
      // We just return an empty box so it shows through without overlapping.
      return const SizedBox.shrink();
    }

    // Default layout for other slides
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 54),
      child: Column(
        children: [
          const SizedBox(height: 60),
          const Spacer(flex: 1),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_open_rounded,
                    color: LunaraTheme.electricViolet,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 24),
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

  Widget _buildTextSection(Map<String, String> slide, int index) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dot Indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (dotIndex) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: _currentPage == dotIndex ? 24 : 6,
                  decoration: BoxDecoration(
                    color: _currentPage == dotIndex
                        ? const Color(0xFFb952eb)
                        : const Color(0xFF6A1B9A).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Text block
            Text(
              index == 0
                  ? 'Find your kind of people.'
                  : (slide['tagline'] ?? ''),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              index == 0
                  ? 'No forcing. No pretending.\nJust good company.'
                  : (slide['subtitle'] ?? ''),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonSection() {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: GestureDetector(
          onTap: _handleNext,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[300]!, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.send_rounded,
                color: Color(0xFF4A148C), // Dark purple arrow
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingIcon extends StatelessWidget {
  final IconData icon;
  final double rotate;

  const _FloatingIcon({required this.icon}) : rotate = 0;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate,
      child: Icon(icon, color: Colors.white, size: 40),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final double rotate;

  const _Pill({required this.text}) : rotate = 0;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFa239ea).withValues(alpha: 0.95),
              const Color(0xFF7F00FF).withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
