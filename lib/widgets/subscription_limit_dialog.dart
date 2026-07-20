import 'dart:math';
import 'package:flutter/material.dart';
import '../screens/profile/vip_membership_screen.dart';

/// Feature context for the limit dialog — determines messaging and icon.
enum SubLimitFeature {
  dailyLikes,
  superLike,
  backtrack,
  strangerMeet,
  partyCreation,
  hideProfile,
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
    title: "You've Used All Your\nDaily Likes",
    subtitle: "Upgrade to Lunara VIP for unlimited likes every day — never miss a connection!",
    benefitHeader: "What you get with VIP:",
    benefits: [
      "♾️ Unlimited daily likes",
      "⭐ Super likes every week",
      "⏪ Backtrack your last swipe",
      "👁️ See who liked you",
      "🚀 Priority visibility boost",
    ],
    gradientColors: [Color(0xFFFF4B7D), Color(0xFFFF8C55)],
  ),
  SubLimitFeature.superLike: _FeatureConfig(
    emoji: '⭐',
    title: "No Super Likes\nRemaining",
    subtitle: "Super Likes show someone you're seriously interested. Get more with a VIP plan!",
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
    title: "Party Creation is\na VIP Feature",
    subtitle: "Host and manage group nights out with your crew — a premium Lunara VIP perk.",
    benefitHeader: "Party Planning includes:",
    benefits: [
      "🥂 Create group plans at venues",
      "💸 Collect split payments",
      "📲 Invite matches & friends",
      "🎫 Generate party tickets",
      "🎟️ Available from Core plan",
    ],
    gradientColors: [Color(0xFFFFB703), Color(0xFFFF4B7D)],
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
      "♾️ Unlimited likes & matches",
      "⭐ Super likes & boosts",
      "🤝 Stranger Meet access",
      "🎉 Party creation",
      "👁️ See who viewed you",
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
  if (code == 'SUBSCRIPTION_REQUIRED') {
    // Try to infer from context
    return SubLimitFeature.generic;
  }
  if (action == 'superlike') return SubLimitFeature.superLike;
  if (action == 'like') return SubLimitFeature.dailyLikes;
  return SubLimitFeature.generic;
}

SubLimitFeature featureFromActionOrCode({String? action, String? code}) {
  if (action == 'superlike') return SubLimitFeature.superLike;
  if (action == 'like') return SubLimitFeature.dailyLikes;
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
    final cfg = _configs[widget.feature] ?? _configs[SubLimitFeature.generic]!;
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

              SingleChildScrollView(
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VIPMembershipScreen(),
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
                            children: const [
                              Text(
                                '👑',
                                style: TextStyle(fontSize: 20),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'UPGRADE TO VIP',
                                style: TextStyle(
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
