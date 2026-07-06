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
      'tagline': 'Find your kind of people',
      'subtitle': 'No forcing, No pretending\nJust good company.',
      'bg': 'assets/images/welcome_bg.png',
    },
    {
      'tagline': 'Less texting. More showing up.',
      'subtitle':
          'Find people who actually want to grab coffee, hit a gig,\nor explore the city.',
      'bg': 'assets/images/welcome_bg_2.png',
    },
    {
      'tagline': 'Main Character nights only',
      'subtitle':
          'Exclusive perks, premium experiences, and plans worth\ncanceling your Netflix for.',
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
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        slide['tagline'] ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        slide['subtitle'] ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: _handleNext,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.5),
                              width: 6,
                            ),
                          ),
                          child: Transform.rotate(
                            angle: 0, // Rotate send icon slightly right
                            child: const Icon(
                              Icons.send,
                              color: LunaraTheme.electricViolet,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ],
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
