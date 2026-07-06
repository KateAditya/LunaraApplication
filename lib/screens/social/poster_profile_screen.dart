import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../discovery/split_payment_screen.dart';
import '../../services/api_service.dart';

class PosterProfileScreen extends StatefulWidget {
  final Map<String, dynamic> poster;
  final Map<String, dynamic> feedItem;

  const PosterProfileScreen({
    super.key,
    required this.poster,
    required this.feedItem,
  });

  @override
  State<PosterProfileScreen> createState() => _PosterProfileScreenState();
}

class _PosterProfileScreenState extends State<PosterProfileScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  int _currentPage = 0;

  // Mock gallery pages for the poster
  late List<Map<String, dynamic>> _pages;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pages = [
      {
        'image': widget.poster['avatar'] ?? 'assets/images/profiles/zane.png',
        'type': 'profile',
      },
      {
        'image': 'https://picsum.photos/seed/poster1/400/600',
        'type': 'photo',
        'caption': 'Last night out 🎵',
      },
      {
        'image': 'https://picsum.photos/seed/poster2/400/600',
        'type': 'photo',
        'caption': 'Weekend rooftop vibes ✨',
      },
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      body: Stack(
        children: [
          // Background blurred photo
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              return _buildPage(_pages[index], index);
            },
          ),
          // Top bar
          SafeArea(child: Column(children: [_buildTopBar(context)])),
          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(context),
          ),
          // Page indicators
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 0,
            right: 0,
            child: Center(child: _buildPageIndicators()),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(Map<String, dynamic> page, int index) {
    final isProfile = page['type'] == 'profile';
    final String imagePath = page['image'] as String;
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: imagePath.startsWith('http')
              ? NetworkImage(imagePath) as ImageProvider
              : AssetImage(imagePath),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.35),
            BlendMode.darken,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
            stops: const [0.4, 1.0],
          ),
        ),
        child: isProfile
            ? null
            : Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          page['caption'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.black45,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Spacer(),
          // Swipe hint
          const Row(
            children: [
              Icon(Icons.swipe, color: Colors.white54, size: 16),
              SizedBox(width: 6),
              Text(
                'Swipe for photos',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicators() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_pages.length, (index) {
        final isActive = _currentPage == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isActive ? 20 : 6,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white30,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    final poster = widget.poster;
    final matchPct = ApiService.calculateMatchPercentage(poster);
    final name = poster['name'] ?? 'Unknown';
    final profession = poster['profession'] ?? 'Product Designer';
    final education = poster['education'] ?? 'IIT Pune';
    final age = poster['age'] ?? 26;
    final bio =
        poster['bio'] ?? 'Night owl. Music lover. Here for good vibes only.';
    final venueName = widget.feedItem['venueName'] ?? 'Unknown Venue';
    final planTime = widget.feedItem['planTime'] ?? '22:00';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            LunaraTheme.midnightBlack.withValues(alpha: 0.98),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + Match %
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name, $age',
                      style: LunaraTheme.headingStyle.copyWith(fontSize: 26),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.work_outline,
                          color: Colors.white38,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          profession,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.school_outlined,
                          color: Colors.white38,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          education,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Match percentage badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      LunaraTheme.primaryDeep.withValues(alpha: 0.8),
                      LunaraTheme.primaryRich.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      '$matchPct%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'MATCH',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Bio
          Text(
            bio,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Plan info
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderRadius: BorderRadius.circular(12),
            borderColor: LunaraTheme.accentVivid.withValues(alpha: 0.25),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  color: LunaraTheme.accentVivid,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Planning to go to $venueName at $planTime',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Action buttons
          Row(
            children: [
              // Pass
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white38,
                    size: 18,
                  ),
                  label: const Text(
                    'PASS',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Join
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LunaraTheme.purpleGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Join request sent to $name!'),
                          backgroundColor: LunaraTheme.primaryDeep,
                        ),
                      );
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (!mounted) return;
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SplitPaymentScreen(),
                          ),
                        );
                      });
                    },
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text(
                      'JOIN & PAY',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
