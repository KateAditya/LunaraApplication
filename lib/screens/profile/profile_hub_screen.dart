import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vip_membership_screen.dart';
import 'points_rewards_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'safety_check_screen.dart';
import '../post_booking/ticket_pocket_screen.dart';
import '../post_booking/booking_history_screen.dart';
import '../onboarding/welcome_carousel.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';
import '../../widgets/lunara_profile_image.dart';

class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  User? _currentUser;
  bool _isLoading = true;

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
        _isLoading = false;
      });
    }
  }

  int _calculateCompletion() {
    if (_currentUser == null) return 0;
    int completed = 0;
    int total = 8;

    if (_currentUser!.firstName.trim().isNotEmpty) completed++;
    if (_currentUser!.lastName.trim().isNotEmpty) completed++;
    if (_currentUser!.email.trim().isNotEmpty) completed++;
    if (_currentUser!.phone.trim().isNotEmpty) completed++;
    if (_currentUser!.profilePhoto != null &&
        _currentUser!.profilePhoto!.isNotEmpty)
      completed++;
    if (_currentUser!.bio != null && _currentUser!.bio!.isNotEmpty) completed++;
    if (_currentUser!.city != null && _currentUser!.city!.isNotEmpty)
      completed++;
    if (_currentUser!.gender != null && _currentUser!.gender!.isNotEmpty)
      completed++;

    return ((completed / total) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          color: LunaraTheme.electricViolet,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileHeader(context),
                const SizedBox(height: 12),
                _buildVIPBanner(context),
                const SizedBox(height: 40),
                _buildStatsRow(),
                const SizedBox(height: 40),
                _buildSectionHeader('MANAGE ACCOUNT'),
                const SizedBox(height: 16),
                _buildMenuSection(context),
                const SizedBox(height: 32),
                _buildLogoutButton(context),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          children: [
            Stack(
              children: [
                LunaraProfileImage(
                  user: _currentUser,
                  radius: 42,
                  showGradientBorder: true,
                  borderWidth: 3,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: LunaraTheme.electricViolet,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (_currentUser != null &&
                            _currentUser!.fullName.trim().isNotEmpty)
                        ? _currentUser!.fullName.toUpperCase()
                        : 'LUNARA USER',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: Colors.black,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: LunaraTheme.electricViolet,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'SOCIALLY VERIFIED',
                        style: TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final completion = _calculateCompletion();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PROFILE COMPLETION',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                '$completion%',
                                style: const TextStyle(
                                  color: LunaraTheme.electricViolet,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: completion / 100,
                              minHeight: 4,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                LunaraTheme.electricViolet,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _buildVIPBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const VIPMembershipScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFDF5), Color(0xFFFFF9E6)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.amber,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LUNARA VIP • GOLD',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF927900),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '4 active benefits • Priority entry active',
                    style: TextStyle(
                      color: Color(0xFFB8860B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF927900)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          _statItem('24', 'BOOKINGS'),
          _buildVerticalDivider(),
          _statItem('120', 'MATCHES'),
          _buildVerticalDivider(),
          _statItem('4.8k', 'POINTS'),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(height: 30, width: 1, color: Colors.grey[100]);
  }

  Widget _statItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    return Column(
      children: [
        _menuTile(
          Icons.confirmation_num_rounded,
          'My Tickets',
          'Active and past event tickets',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TicketPocketScreen()),
          ),
        ),
        _menuTile(
          Icons.history_rounded,
          'Booking History',
          'Past reservations and events',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BookingHistoryScreen()),
          ),
        ),
        _menuTile(
          Icons.wallet_rounded,
          'Lunara Wallet',
          'Pay and earn rewards',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PointsRewardsScreen(),
            ),
          ),
        ),
        _menuTile(
          Icons.star_rounded,
          'Membership Details',
          'Manage your VIP subscription',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const VIPMembershipScreen(),
            ),
          ),
        ),
        _menuTile(
          Icons.settings_rounded,
          'App Settings',
          'Privacy, Notifications, Safety',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsScreen()),
          ),
        ),
        _menuTile(
          Icons.verified_user_rounded,
          'Safety Check',
          'Review your tonight\'s experience',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SafetyCheckScreen(user: _currentUser),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.grey[50]!),
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: LunaraTheme.electricViolet, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.black12,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () async {
          await ApiService.logout();
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const WelcomeCarousel()),
              (route) => false,
            );
          }
        },
        child: const Text(
          'LOGOUT',
          style: TextStyle(
            color: Colors.redAccent,
            letterSpacing: 2,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
