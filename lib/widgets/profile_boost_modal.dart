import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/subscription_provider.dart';
import '../screens/profile/vip_membership_screen.dart';
import 'top_notification_banner.dart';

class ProfileBoostModal extends StatefulWidget {
  const ProfileBoostModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProfileBoostModal(),
    );
  }

  @override
  State<ProfileBoostModal> createState() => _ProfileBoostModalState();
}

class _ProfileBoostModalState extends State<ProfileBoostModal> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTimeRemaining(DateTime? expiresAt) {
    if (expiresAt == null) return '00:00';
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return '00:00';
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${minutes}m ${seconds}s';
    }
    return '$minutes:$seconds';
  }

  Future<void> _handleActivateBoost() async {
    final provider = SubscriptionProvider.instance;

    // Validate if user has boosts or unlimited
    final validation = provider.validateAction(VipAction.boost);
    if (!validation.allowed) {
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const VIPMembershipScreen(initialTabIndex: 1),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await provider.activateBoost();
      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result['success'] == true) {
        if (mounted) {
          Navigator.pop(context);
        }
        final message = result['message'] ?? 'Profile Boost activated for 30 minutes!';
        TopNotificationBanner.show(
          title: 'Profile Boost Activated! ⚡',
          body: 'Your profile is now spotlighted at the top of local discovery feeds.',
          iconData: Icons.bolt_rounded,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xFFFFB703), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1B4B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        final message = result['message'] ?? 'Could not activate boost. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error activating boost: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionProvider.instance,
      builder: (context, _) {
        final provider = SubscriptionProvider.instance;
        final isBoostActive = provider.isBoostActive;
        final expiresAt = provider.boostExpiresAt;
        final boostsRemaining = provider.boostsRemaining;
        final isUnlimited = provider.isElite || provider.status.isUnlimitedBoosts;

        final isCurrentlySpotlighted = isBoostActive && expiresAt != null && expiresAt.isAfter(DateTime.now());

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Glowing Icon Header
                  ScaleTransition(
                    scale: isCurrentlySpotlighted ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB703), Color(0xFFFB8500)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFB703).withValues(alpha: isCurrentlySpotlighted ? 0.45 : 0.25),
                            blurRadius: isCurrentlySpotlighted ? 24 : 16,
                            spreadRadius: isCurrentlySpotlighted ? 4 : 2,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.bolt_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title
                  Text(
                    isCurrentlySpotlighted ? 'PROFILE SPOTLIGHT ACTIVE' : 'BOOST YOUR PROFILE',
                    style: const TextStyle(
                      fontFamily: 'AllroundGothic',
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),

                  // Subtitle / Status Description
                  Text(
                    isCurrentlySpotlighted
                        ? 'Your profile is spotlighted at the very top of local Discovery & Social feeds.'
                        : 'Jump straight to the top of everyone\'s feed for the next 30 minutes and get up to 10x more profile views.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),

                  // Active Countdown Box (if spotlight is currently active)
                  if (isCurrentlySpotlighted) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'LIVE SPOTLIGHT REMAINING',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatTimeRemaining(expiresAt),
                            style: const TextStyle(
                              fontFamily: 'AllroundGothic',
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFB45309),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Key Benefits List
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        _benefitRow(
                          Icons.trending_up_rounded,
                          '10x More Profile Views',
                          'Immediate priority in matches & live discovery.',
                        ),
                        const Divider(height: 18, color: Color(0xFFE5E7EB)),
                        _benefitRow(
                          Icons.star_rounded,
                          'Top Feed Ranking',
                          'Ranked above standard profiles for 30 minutes.',
                        ),
                        const Divider(height: 18, color: Color(0xFFE5E7EB)),
                        _benefitRow(
                          Icons.auto_awesome_rounded,
                          'Spotlight Badge & Glow',
                          'Golden halo around your avatar across the app.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Available Balance Pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isUnlimited || boostsRemaining > 0
                              ? const Color(0xFFFEF3C7)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isUnlimited || boostsRemaining > 0
                                ? const Color(0xFFFCD34D)
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 16,
                              color: isUnlimited || boostsRemaining > 0
                                  ? const Color(0xFFD97706)
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isUnlimited
                                  ? 'Unlimited Boosts (VIP Elite)'
                                  : '$boostsRemaining Boost${boostsRemaining == 1 ? '' : 's'} Remaining',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isUnlimited || boostsRemaining > 0
                                    ? const Color(0xFF92400E)
                                    : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Primary Action Button
                  if (isCurrentlySpotlighted) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFFB703), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          'KEEP SPOTLIGHT ACTIVE',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ] else if (isUnlimited || boostsRemaining > 0) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _handleActivateBoost(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB703),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: EdgeInsets.zero,
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB703), Color(0xFFFB8500)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                                      SizedBox(width: 8),
                                      Text(
                                        'ACTIVATE BOOST (30 MIN)',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const VIPMembershipScreen(initialTabIndex: 1),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LunaraTheme.electricViolet,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'GET BOOST PACK (FROM ₹49)',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _benefitRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB703).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFFD97706), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
