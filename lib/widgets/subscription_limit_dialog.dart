import 'dart:math';
import 'package:flutter/material.dart';
import '../screens/profile/vip_membership_screen.dart';
import '../services/subscription_provider.dart';

/// Feature context for the limit dialog — determines messaging and icon.
enum SubLimitFeature {
  dailyLikes,
  superLike,
  boost,
  backtrack,
  strangerMeet,
  partyCreation,
  hideProfile,
  whoLikedMe,
  generic,
}

/// Config object per feature.
class _FeatureConfig {
  final String emoji;
  final String title;
  final String subtitle;
  final String benefitHeader;
  final List<String> benefits;
  final List<Color> gradientColors;

  const _FeatureConfig({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.benefitHeader,
    required this.benefits,
    required this.gradientColors,
  });
}

const _configs = <SubLimitFeature, _FeatureConfig>{
  SubLimitFeature.dailyLikes: _FeatureConfig(
    emoji: '❤️',
    title: "Daily Like Limit\nReached",
    subtitle: "You've used all your daily likes for today. Upgrade your plan to get more likes!",
    benefitHeader: "What you get with VIP:",
    benefits: [
      "♾️ Configured daily likes or unlimited",
      "⭐ Super likes every cycle",
      "⏪ Backtrack your last swipe",
      "👁️ See who liked you",
      "🚀 Priority visibility boost",
    ],
    gradientColors: [Color(0xFFFF4B7D), Color(0xFFFF8C55)],
  ),
  SubLimitFeature.superLike: _FeatureConfig(
    emoji: '⭐',
    title: "Super Likes are a\nVIP Feature",
    subtitle: "Show someone you're especially interested in with priority Super Likes!",
    benefitHeader: "Super likes by plan:",
    benefits: [
      "💙 Core: 3 super likes/week",
      "💜 Plus: 10 super likes/week",
      "🔮 Pro: 14 super likes/week",
      "👑 Elite: Unlimited super likes",
      "✨ Renews every cycle",
    ],
    gradientColors: [Color(0xFF7B2FFF), Color(0xFFB44FFF)],
  ),
  SubLimitFeature.boost: _FeatureConfig(
    emoji: '🚀',
    title: "Boost Your Profile\nwith VIP",
    subtitle: "Boost your profile to get up to 10x more visibility in discovery feeds tonight.",
    benefitHeader: "Boosts by plan:",
    benefits: [
      "💜 Plus: 2 free boosts per cycle",
      "🔮 Pro: 4 free boosts per cycle",
      "👑 Elite: Unlimited boosts",
      "⚡ In-App Boost packs from ₹49",
      "🚀 10x more profile views & matches",
    ],
    gradientColors: [Color(0xFFFFB703), Color(0xFF7F00FF)],
  ),
  SubLimitFeature.backtrack: _FeatureConfig(
    emoji: '⏪',
    title: "No Backtracks\nRemaining",
    subtitle: "Accidentally swiped? Backtrack lets you undo your last swipe. Upgrade for more!",
    benefitHeader: "Backtracks by plan:",
    benefits: [
      "🟦 Core: 5 backtracks/day",
      "🟪 Plus: 10 backtracks/day",
      "🔮 Pro: 15 backtracks/day",
      "👑 Elite: Unlimited backtracks",
      "🔄 Resets every midnight",
    ],
    gradientColors: [Color(0xFF00A9FF), Color(0xFF7B2FFF)],
  ),
  SubLimitFeature.strangerMeet: _FeatureConfig(
    emoji: '🤝',
    title: "Stranger Meet is\na VIP Feature",
    subtitle: "Create verified meetups at your favourite venues — exclusively for Lunara VIP members.",
    benefitHeader: "Stranger Meet includes:",
    benefits: [
      "📍 Post meetups at any venue",
      "✅ Verified profile badge",
      "🔒 Safe & moderated requests",
      "💬 Connect before you meet",
      "🎟️ Available from Core plan",
    ],
    gradientColors: [Color(0xFF00BFA5), Color(0xFF7B2FFF)],
  ),
  SubLimitFeature.partyCreation: _FeatureConfig(
    emoji: '🎉',
    title: "Party Plan Limit\nReached",
    subtitle: "Free users can create 1 Party Plan during the current 7-day period. Upgrade to VIP to create more Party Plans!",
    benefitHeader: "VIP Party Plan Benefits:",
    benefits: [
      "🥂 Create multiple party plans",
      "⭐ Priority Live Feed placement",
      "💸 Collect split payments",
      "📲 Direct invites to matches",
      "🎟️ Instant party ticketing",
    ],
    gradientColors: [Color(0xFFFFB703), Color(0xFFFF4B7D)],
  ),
  SubLimitFeature.whoLikedMe: _FeatureConfig(
    emoji: '❤️',
    title: "People Like You",
    subtitle: "You have people waiting to connect with you. Upgrade to VIP to see exactly who liked you!",
    benefitHeader: "Who Liked You Perks:",
    benefits: [
      "✓ See who liked you instantly",
      "✓ Match faster with Like Back",
      "✓ Unmask all profile photos & bios",
      "✓ Filter by super likes received",
      "✓ Full VIP membership benefits",
    ],
    gradientColors: [Color(0xFFFF4B7D), Color(0xFF7B2FFF)],
  ),
  SubLimitFeature.hideProfile: _FeatureConfig(
    emoji: '🙈',
    title: "Hide Profile is a\nVIP Feature",
    subtitle: "Go ghost mode! Control your visibility and browse anonymously with Lunara VIP.",
    benefitHeader: "Hide Profile Benefits:",
    benefits: [
      "🙈 Browse profiles without being seen",
      "🕵️ Exclusive Ghost Mode toggle",
      "✨ Control who sees your activity",
      "👑 Full VIP membership perks",
      "🚀 Priority matching when unhidden",
    ],
    gradientColors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
  ),
  SubLimitFeature.generic: _FeatureConfig(
    emoji: '👑',
    title: "Upgrade to\nLunara VIP",
    subtitle: "Unlock the full Lunara experience. Premium features are waiting for you!",
    benefitHeader: "VIP includes everything:",
    benefits: [
      "♾️ Configured daily likes & matches",
      "⭐ Super likes & profile boosts",
      "🤝 Stranger Meet access",
      "🎉 Party creation privileges",
      "👁️ See who liked you",
    ],
    gradientColors: [Color(0xFF7B2FFF), Color(0xFFFF4B7D)],
  ),
};

/// Shows the subscription limit bottom sheet.
Future<void> showSubscriptionLimitDialog(
  BuildContext context, {
  SubLimitFeature feature = SubLimitFeature.generic,
  String? customMessage,
}) {
  final provider = SubscriptionProvider.instance;

  // ── Top tier (Elite) users have unlimited everything. Suppress limit popups.
  if (provider.isElite) {
    debugPrint('[SubscriptionLimitDialog] Suppressed limit dialog for Elite VIP user.');
    return Future.value();
  }

  // ── Suppress dailyLikes popup only if user has unlimited likes
  if (provider.status.hasUnlimitedLikes && feature == SubLimitFeature.dailyLikes) {
    debugPrint('[SubscriptionLimitDialog] Suppressed dailyLikes dialog for unlimited user.');
    return Future.value();
  }

  // ── Suppress whoLikedMe popup if user already has access
  if (provider.status.canSeeWhoLiked && feature == SubLimitFeature.whoLikedMe) {
    return Future.value();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => _SubscriptionLimitSheet(
      feature: feature,
      customMessage: customMessage,
    ),
  );
}

/// Parses the API error code into a [SubLimitFeature].
SubLimitFeature featureFromCode(String? code, {String? action}) {
  if (code == 'PARTY_PLAN_LIMIT_REACHED' ||
      code == 'PARTY_PLAN_DAILY_LIMIT_REACHED' ||
      action == 'party_plan' ||
      action == 'party_creation') {
    return SubLimitFeature.partyCreation;
  }
  if (code == 'SUBSCRIPTION_REQUIRED') {
    // Try to infer from context
    return SubLimitFeature.generic;
  }
  if (action == 'superlike') return SubLimitFeature.superLike;
  if (action == 'like') return SubLimitFeature.dailyLikes;
  return SubLimitFeature.generic;
}

SubLimitFeature featureFromActionOrCode({String? action, String? code}) {
  if (code == 'PARTY_PLAN_LIMIT_REACHED' ||
      code == 'PARTY_PLAN_DAILY_LIMIT_REACHED' ||
      action == 'party_plan' ||
      action == 'party_creation') {
    return SubLimitFeature.partyCreation;
  }
  if (action == 'superlike') return SubLimitFeature.superLike;
  if (action == 'like') return SubLimitFeature.dailyLikes;
  if (action == 'boost' || action == 'profile_boost') return SubLimitFeature.boost;
  if (action == 'backtrack') return SubLimitFeature.backtrack;
  if (code == 'SUBSCRIPTION_REQUIRED') return SubLimitFeature.generic;
  return SubLimitFeature.generic;
}

// ─── Internal Bottom Sheet ────────────────────────────────────────────────────

class _SubscriptionLimitSheet extends StatefulWidget {
  final SubLimitFeature feature;
  final String? customMessage;

  const _SubscriptionLimitSheet({required this.feature, this.customMessage});

  @override
  State<_SubscriptionLimitSheet> createState() => _SubscriptionLimitSheetState();
}

class _SubscriptionLimitSheetState extends State<_SubscriptionLimitSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = SubscriptionProvider.instance;
    final isPaid = provider.isPaid;
    // For paid users who have run out of superlikes/boosts/backtracks,
    // show an add-on CTA rather than the generic 'VIP Feature' messaging.
    final showAddonCta = isPaid &&
        (widget.feature == SubLimitFeature.superLike ||
         widget.feature == SubLimitFeature.boost ||
         widget.feature == SubLimitFeature.backtrack);

    _FeatureConfig cfg;
    if (showAddonCta) {
      // Paid user: override title/subtitle to reflect add-on context
      final baseCfg = _configs[widget.feature] ?? _configs[SubLimitFeature.generic]!;
      cfg = _FeatureConfig(
        emoji: baseCfg.emoji,
        title: widget.feature == SubLimitFeature.superLike
            ? 'Super Likes\nUsed Up!'
            : widget.feature == SubLimitFeature.boost
                ? 'Profile Boosts\nUsed Up!'
                : 'Backtracks\nUsed Up!',
        subtitle: widget.feature == SubLimitFeature.superLike
            ? 'You\'ve used all your Super Likes for this cycle. Get an add-on pack to keep super-liking tonight!'
            : widget.feature == SubLimitFeature.boost
                ? 'You\'ve used all your Profile Boosts. Get a Boost pack to stay spotlighted!'
                : 'You\'ve used all your Backtracks for today. Get a Backtrack add-on to keep undoing swipes!',
        benefitHeader: 'Add-on packs include:',
        benefits: widget.feature == SubLimitFeature.superLike
            ? [
                '⭐ +5 Super Likes from ₹99',
                '⭐ +15 Super Likes from ₹249',
                '✨ Instant top-profile alert to matches',
                '💜 Priority placement in their feed',
                '🔄 Never expires during your plan cycle',
              ]
            : widget.feature == SubLimitFeature.boost
                ? [
                    '⚡ +1 Boost from ₹49',
                    '⚡ +3 Boosts from ₹129',
                    '🚀 10x more profile views for 30 min',
                    '📈 Jump to top of discovery feed',
                    '🔔 Real-time activity alerts',
                  ]
                : [
                    '⏪ +10 Backtracks from ₹49',
                    '🔄 Undo swipes any time today',
                    '♾️ No reset timer on add-on credits',
                    '✅ Works on top of your plan limit',
                  ],
        gradientColors: baseCfg.gradientColors,
      );
    } else {
      cfg = _configs[widget.feature] ?? _configs[SubLimitFeature.generic]!;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF13131B) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1C1C26) : const Color(0xFFF8F8FF);

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.0).withValues(
                    alpha: isDark ? 0.15 : 0.2,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  children: [
                    // Animated Emoji Badge
                    ScaleTransition(
                      scale: _scaleAnim,
                      child: _EmojiOrb(
                        emoji: cfg.emoji,
                        gradientColors: cfg.gradientColors,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      cfg.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Subtitle / server message
                    Text(
                      widget.customMessage ?? cfg.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Benefits card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: cfg.gradientColors.first.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cfg.benefitHeader.toUpperCase(),
                            style: TextStyle(
                              color: cfg.gradientColors.first,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ...cfg.benefits.map((b) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  b,
                                  style: TextStyle(
                                    color: isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
                                    fontSize: 14,
                                    height: 1.3,
                                  ),
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // CTA Button — Upgrade
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: cfg.gradientColors,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: cfg.gradientColors.first.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            // For paid users: go to add-ons tab (index 1)
                            // For free users: go to VIP plans tab (index 0)
                            final targetTab = showAddonCta
                                ? 1
                                : (widget.feature == SubLimitFeature.superLike ? 1 : 0);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VIPMembershipScreen(initialTabIndex: targetTab),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                showAddonCta ? '⚡' : (provider.isPaid ? '⚡' : '👑'),
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                showAddonCta ? 'GET ADD-ON PACK' : (provider.isPaid ? 'GET ADD-ON PACK' : 'UPGRADE TO VIP'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Dismiss
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Maybe Later',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Animated emoji orb ───────────────────────────────────────────────────────

class _EmojiOrb extends StatefulWidget {
  final String emoji;
  final List<Color> gradientColors;

  const _EmojiOrb({required this.emoji, required this.gradientColors});

  @override
  State<_EmojiOrb> createState() => _EmojiOrbState();
}

class _EmojiOrbState extends State<_EmojiOrb> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final glow = 0.3 + 0.2 * sin(_pulse.value * pi);
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.gradientColors.first.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.gradientColors.first.withValues(alpha: glow),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: widget.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.emoji,
          style: const TextStyle(fontSize: 44),
        ),
      ),
    );
  }
}
