import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vip_membership_screen.dart';
import 'lunara_wallet_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'safety_check_screen.dart';
import '../post_booking/ticket_pocket_screen.dart';
import '../post_booking/booking_history_screen.dart';
import '../onboarding/welcome_carousel.dart';
import '../../services/api_service.dart';
import '../../services/subscription_provider.dart';
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
    User? user = await ApiService.fetchProfile();
    user ??= ApiService.cachedCurrentUser;

    if (user == null) {
      final customers = await ApiService.fetchCustomers();
      if (customers.isNotEmpty) {
        final currentId = ApiService.currentUserId;
        Map<String, dynamic>? match;
        if (currentId != null && currentId.isNotEmpty) {
          try {
            match = customers.firstWhere((c) => c['id'] == currentId || c['_id'] == currentId);
          } catch (_) {}
        }
        match ??= customers.first;
        user = User.fromJson(match);
        ApiService.cachedCurrentUser = user;
      }
    }

    if (mounted) {
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
    }
  }

  int _calculateCompletion() {
    if (_currentUser == null) return 0;
    return _currentUser!.profileCompletionPercentage;
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
        MaterialPageRoute(builder: (_) => ProfileScreen(user: _currentUser)),
      ).then((_) => _loadProfile()),
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
                      final missing = _currentUser?.incompleteFields ?? [];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'PROFILE COMPLETION',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
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
                          if (missing.isNotEmpty && completion < 100) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Missing: ${missing.take(3).join(", ")}${missing.length > 3 ? "..." : ""}',
                              style: const TextStyle(
                                color: Colors.deepOrangeAccent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
    final subscription = SubscriptionScope.of(context).status;

    final isPaid = subscription.isPaid;
    final tier = subscription.tier;
    final planName = subscription.planName;
    final remainingDays = subscription.remainingDays;
    final superlikes = subscription.superlikesRemaining;
    final boosts = subscription.boostsRemaining;

    // Color theme per tier
    Color primaryColor;
    Color subTextColor;
    List<Color> gradientColors;
    IconData iconData;

    switch (tier) {
      case 'ELITE':
        primaryColor = const Color(0xFFD4AF37);
        subTextColor = const Color(0xFF927900);
        gradientColors = [const Color(0xFFFFFDF5), const Color(0xFFFFF7D6)];
        iconData = Icons.workspace_premium_rounded;
        break;
      case 'PRO':
        primaryColor = const Color(0xFFE100FF);
        subTextColor = const Color(0xFF7F00FF);
        gradientColors = [const Color(0xFFFAF0FF), const Color(0xFFF3E5F5)];
        iconData = Icons.auto_awesome_rounded;
        break;
      case 'PLUS':
        primaryColor = const Color(0xFF7F00FF);
        subTextColor = const Color(0xFF5E00B8);
        gradientColors = [const Color(0xFFF3E5F5), const Color(0xFFEDE7F6)];
        iconData = Icons.star_rounded;
        break;
      case 'CORE':
        primaryColor = const Color(0xFF00A9FF);
        subTextColor = const Color(0xFF0066CC);
        gradientColors = [const Color(0xFFE3F2FD), const Color(0xFFE0F7FA)];
        iconData = Icons.verified_user_rounded;
        break;
      default:
        primaryColor = LunaraTheme.electricViolet;
        subTextColor = Colors.black54;
        gradientColors = [const Color(0xFFFFF5F8), const Color(0xFFF3E5F5)];
        iconData = Icons.auto_awesome_rounded;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const VIPMembershipScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: primaryColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isPaid
                              ? 'LUNARA $planName • $tier'
                              : 'GET LUNARA VIP',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: isPaid ? primaryColor : Colors.black,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPaid && remainingDays > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$remainingDays d left',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPaid
                        ? '⭐ Super Likes: $superlikes  •  ⚡ Boosts: $boosts'
                        : 'Unlock Unlimited Likes, Super Likes & Priority Boosts',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final bookings = _currentUser?.bookingsCount ?? 0;
    final matches = _currentUser?.matchesCount ?? 0;
    final points = _currentUser?.pointsCount ?? 0;

    String pointsStr;
    if (points >= 1000) {
      pointsStr = '${(points / 1000).toStringAsFixed(1)}k';
      if (pointsStr.endsWith('.0k')) {
        pointsStr = pointsStr.replaceAll('.0k', 'k');
      }
    } else {
      pointsStr = points.toString();
    }

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
          _statItem(bookings.toString(), 'BOOKINGS'),
          _buildVerticalDivider(),
          _statItem(matches.toString(), 'MATCHES'),
          _buildVerticalDivider(),
          _statItem(pointsStr, 'POINTS'),
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
            MaterialPageRoute(builder: (context) => const LunaraWalletScreen()),
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
