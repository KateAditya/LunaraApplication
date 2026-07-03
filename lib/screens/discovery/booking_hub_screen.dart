import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../core/theme.dart';
import 'group_party_booking_screen.dart';

class BookingHubScreen extends StatefulWidget {
  const BookingHubScreen({super.key});

  @override
  State<BookingHubScreen> createState() => _BookingHubScreenState();
}

class _BookingHubScreenState extends State<BookingHubScreen> {
  // Mock data for featured profiles
  final List<Map<String, String>> _featuredProfiles = [
    {'name': 'Alex R.', 'avatar': 'assets/images/profiles/zane.png'},
    {'name': 'Sarah J.', 'avatar': 'assets/images/profiles/lyra.png'},
    {'name': 'Mike T.', 'avatar': 'assets/images/profiles/elara.png'},
    {'name': 'Lily W.', 'avatar': 'assets/images/profiles/zane.png'},
    {'name': 'Ryan P.', 'avatar': 'assets/images/profiles/lyra.png'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('BOOKING HUB', style: TextStyle(fontFamily: 'AllroundGothic', letterSpacing: 2)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnimatedBanner(),
            const SizedBox(height: 24),
            _buildActionButtons(context),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'FEATURED PROFILES',
                style: TextStyle(fontFamily: 'AllroundGothic', fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 16),
            _buildProfilesList(),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'ALL USERS',
                style: TextStyle(fontFamily: 'AllroundGothic', fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 16),
            _buildAllUsersList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBanner() {
    final List<Map<String, String>> banners = [
      {'title': 'VIP TABLES', 'subtitle': 'Exclusive access to premium seating', 'color': '0xFF9D4EDD'},
      {'title': 'LIVE EVENTS', 'subtitle': 'Catch the best DJs in town', 'color': '0xFFC084FC'},
      {'title': 'GROUP OFFERS', 'subtitle': 'Special discounts for parties', 'color': '0xFF7B2CBF'},
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: CarouselSlider(
        options: CarouselOptions(
          height: 120.0,
          autoPlay: true,
          autoPlayInterval: const Duration(seconds: 4),
          enlargeCenterPage: true,
          viewportFraction: 0.9,
        ),
        items: banners.map((banner) {
          return Builder(
            builder: (BuildContext context) {
              return Container(
                width: MediaQuery.of(context).size.width,
                margin: const EdgeInsets.symmetric(horizontal: 5.0),
                decoration: BoxDecoration(
                  color: Color(int.parse(banner['color']!)),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.purple.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 5)),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: Icon(Icons.celebration, size: 100, color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            banner['title']!,
                            style: const TextStyle(fontFamily: 'AllroundGothic', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            banner['subtitle']!,
                            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildActionButton(
            title: 'CREATE PLAN',
            subtitle: 'Organize an event and invite your network',
            icon: Icons.edit_calendar_rounded,
            color: LunaraTheme.primaryDeep,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            title: 'PERSONAL INVITE',
            subtitle: 'Send an exclusive invitation to a match',
            icon: Icons.mail_outline_rounded,
            color: LunaraTheme.accentVivid,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            title: 'GROUP PARTY BOOKING',
            subtitle: 'Corporate events, fests, and large gatherings',
            icon: Icons.groups_rounded,
            color: Colors.amber.shade600,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupPartyBookingScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontFamily: 'AllroundGothic', fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilesList() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _featuredProfiles.length,
        itemBuilder: (context, index) {
          final profile = _featuredProfiles[index];
          return Container(
            width: 72,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LunaraTheme.primaryGradient,
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundImage: AssetImage(profile['avatar']!),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  profile['name']!,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllUsersList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: 4,
      itemBuilder: (context, index) {
        final profile = _featuredProfiles[index % _featuredProfiles.length];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[100]!),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: AssetImage(profile['avatar']!),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile['name']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Active recently', style: TextStyle(fontSize: 11, color: Colors.green[600])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('INVITE', style: TextStyle(fontFamily: 'AllroundGothic', color: LunaraTheme.electricViolet, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ],
          ),
        );
      },
    );
  }
}
