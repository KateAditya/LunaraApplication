import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/vip_entitlement_model.dart';
import '../../services/subscription_provider.dart';
import 'vip_membership_screen.dart';

class PlanUsageScreen extends StatelessWidget {
  const PlanUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'PLAN USAGE & QUOTAS',
          style: TextStyle(
            fontFamily: 'AllroundGothic',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 1.2,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const SafeArea(
        child: PlanUsageContent(),
      ),
    );
  }
}

class PlanUsageContent extends StatefulWidget {
  final VoidCallback? onGoToVIPPasses;
  final VoidCallback? onGoToAddons;

  const PlanUsageContent({
    super.key,
    this.onGoToVIPPasses,
    this.onGoToAddons,
  });

  @override
  State<PlanUsageContent> createState() => _PlanUsageContentState();
}

class _PlanUsageContentState extends State<PlanUsageContent> {
  @override
  void initState() {
    super.initState();
    SubscriptionProvider.instance.fetchEntitlementsSummary();
  }

  Future<void> _refresh() async {
    await Future.wait([
      SubscriptionProvider.instance.refresh(),
      SubscriptionProvider.instance.fetchEntitlementsSummary(),
    ]);
  }

  Color _getTierColor(String tier) {
    switch (tier.toUpperCase()) {
      case 'CORE':
        return LunaraTheme.cyberCyan;
      case 'PLUS':
        return LunaraTheme.electricViolet;
      case 'PRO':
        return const Color(0xFFE040FB);
      case 'ELITE':
        return const Color(0xFFFFB703);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionProvider.instance,
      builder: (context, _) {
        final provider = SubscriptionProvider.instance;
        final summary = provider.entitlementsSummary;
        final isLoading = provider.isLoadingEntitlements && summary == null;

        if (isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
          );
        }

        final tier = summary?.planTier ?? provider.tier;
        final planName = summary?.planName ?? (provider.status.isPaid ? 'LUNARA $tier' : 'Free Member');
        final isActive = summary?.isActive ?? provider.status.isActive;
        final remainingDays = summary?.remainingDays ?? provider.status.remainingDays;
        final tierColor = _getTierColor(tier);

        final benefits = summary?.planBenefits ?? [];
        final addons = summary?.activeAddons ?? [];
        final perks = summary?.includedFeaturesChecklist ?? [];

        return RefreshIndicator(
          onRefresh: _refresh,
          color: LunaraTheme.electricViolet,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Active Plan Header Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tierColor.withValues(alpha: 0.15),
                        tierColor.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: tierColor.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: tierColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tier == 'ELITE' ? Icons.workspace_premium_rounded : Icons.star_rounded,
                                  color: tier == 'ELITE' ? Colors.black : Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tier.toUpperCase(),
                                  style: TextStyle(
                                    color: tier == 'ELITE' ? Colors.black : Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isActive && remainingDays > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                '$remainingDays days remaining',
                                style: const TextStyle(
                                  color: Color(0xFF15803D),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        planName.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'AllroundGothic',
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isActive
                            ? 'Your subscription is active with full tier perks & priority allowances.'
                            : 'Upgrade to Lunara VIP to unlock unlimited swipes, super likes & priority boosts.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                if (widget.onGoToAddons != null) {
                                  widget.onGoToAddons!();
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const VIPMembershipScreen(initialTabIndex: 1),
                                    ),
                                  );
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: tierColor),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                'ADD-ONS STORE',
                                style: TextStyle(
                                  color: tierColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                if (widget.onGoToVIPPasses != null) {
                                  widget.onGoToVIPPasses!();
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const VIPMembershipScreen(initialTabIndex: 0),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tierColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                isActive ? 'CHANGE PLAN' : 'UPGRADE VIP',
                                style: TextStyle(
                                  color: tier == 'ELITE' ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Quotas & Feature Usage
                const Text(
                  'QUOTA & USAGE BREAKDOWN',
                  style: TextStyle(
                    fontFamily: 'AllroundGothic',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),

                if (benefits.isEmpty)
                  _buildFallbackBenefits(provider)
                else
                  ...benefits.map((item) => _buildUsageCard(item)),

                const SizedBox(height: 24),

                // Section: Add-on Balances
                if (addons.isNotEmpty) ...[
                  const Text(
                    'ADD-ON INVENTORY',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: addons.map((addon) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.bolt_rounded,
                                  color: LunaraTheme.electricViolet,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  addon.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${addon.remainingQuantity} Left',
                                  style: const TextStyle(
                                    color: Color(0xFF15803D),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Section: Included VIP Perks
                if (perks.isNotEmpty) ...[
                  const Text(
                    'INCLUDED PLAN PRIVILEGES',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...perks.map((perk) => _buildPerkCard(perk)),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsageCard(PlanEntitlementItem item) {
    final isUnlimited = item.isUnlimited;
    final progress = (item.progressPercentage / 100.0).clamp(0.0, 1.0);

    String statusText;
    if (isUnlimited) {
      statusText = 'UNLIMITED';
    } else {
      statusText = '${item.remainingQuantity} / ${item.includedQuantity} left';
    }

    Color progressColor;
    if (isUnlimited) {
      progressColor = const Color(0xFF10B981);
    } else if (item.isLow) {
      progressColor = Colors.orange;
    } else {
      progressColor = LunaraTheme.electricViolet;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                item.icon,
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    if (item.unit.isNotEmpty)
                      Text(
                        item.unit,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: progressColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: isUnlimited ? 1.0 : (1.0 - progress),
              minHeight: 7,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          if (!isUnlimited) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${item.usedQuantity} Used',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                Text(
                  '${item.remainingQuantity} Remaining',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.isLow ? Colors.orange[800] : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFallbackBenefits(SubscriptionProvider provider) {
    final status = provider.status;
    final fallbackItems = [
      PlanEntitlementItem(
        featureKey: 'daily_likes',
        name: 'Daily Likes',
        icon: '❤️',
        includedQuantity: status.dailyLikesLimitInt,
        usedQuantity: status.dailyLikesUsed,
        remainingQuantity: status.dailyLikesRemaining,
        progressPercentage: status.hasUnlimitedLikes ? 0 : ((status.dailyLikesUsed / (status.dailyLikesLimitInt == 0 ? 1 : status.dailyLikesLimitInt)) * 100).toInt(),
        isUnlimited: status.hasUnlimitedLikes,
        unit: 'per day',
      ),
      PlanEntitlementItem(
        featureKey: 'superlike',
        name: 'Super Likes',
        icon: '⭐',
        includedQuantity: status.superlikesPerCycle,
        usedQuantity: (status.superlikesPerCycle - provider.superlikesRemaining).clamp(0, 9999),
        remainingQuantity: provider.superlikesRemaining,
        progressPercentage: status.isElite ? 0 : 50,
        isUnlimited: status.isElite,
        unit: 'per cycle',
      ),
      PlanEntitlementItem(
        featureKey: 'profile_boost',
        name: 'Profile Boosts',
        icon: '⚡',
        includedQuantity: status.boostsPerCycle,
        usedQuantity: (status.boostsPerCycle - provider.boostsRemaining).clamp(0, 9999),
        remainingQuantity: provider.boostsRemaining,
        progressPercentage: status.isElite ? 0 : 50,
        isUnlimited: status.isElite,
        unit: 'per cycle',
      ),
      PlanEntitlementItem(
        featureKey: 'backtrack',
        name: 'Rewinds / Backtracks',
        icon: '⏪',
        includedQuantity: status.dailyBacktrackLimitInt,
        usedQuantity: status.dailyBacktrackUsed,
        remainingQuantity: status.dailyBacktrackRemaining,
        progressPercentage: status.hasUnlimitedBacktracks ? 0 : 20,
        isUnlimited: status.hasUnlimitedBacktracks,
        unit: 'per day',
      ),
    ];

    return Column(
      children: fallbackItems.map((item) => _buildUsageCard(item)).toList(),
    );
  }

  Widget _buildPerkCard(IncludedChecklistItem perk) {
    final isEnabled = perk.isEnabled;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isEnabled ? Colors.white : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isEnabled ? Colors.grey[200]! : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Text(perk.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  perk.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isEnabled ? Colors.black87 : Colors.grey[500],
                  ),
                ),
                Text(
                  perk.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isEnabled ? Colors.grey[600] : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isEnabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            color: isEnabled ? const Color(0xFF10B981) : Colors.grey[400],
            size: 20,
          ),
        ],
      ),
    );
  }
}
