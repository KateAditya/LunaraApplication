// lib/models/plan_status.dart
// Represents the full subscription state for the current user.
// Populated from GET /api/mobile/subscriptions/status

class PlanStatus {
  final bool isActive;
  final String tier; // FREE, CORE, PLUS, PRO, ELITE
  final int tierRank; // 0=FREE, 1=CORE, 2=PLUS, 3=PRO, 4=ELITE
  final String planName;
  final String? packageId;
  final int remainingDays;

  // Engagement counts
  final int superlikesRemaining;
  final int superlikesPerCycle;
  final int boostsRemaining;
  final int boostsPerCycle;

  // Daily feature limits
  final dynamic dailyLikesLimit; // int or 'unlimited'
  final int dailyLikesUsed;
  final dynamic dailyMatchRequestsLimit;
  final int dailyMatchRequestsUsed;
  final dynamic dailyPostsLimit;
  final int dailyPostsUsed;
  final dynamic dailyBacktrackLimit;
  final int dailyBacktrackUsed;

  // Boolean features
  final bool hasPriorityVisibility;
  final bool hasTrustBadge;
  final bool hasEliteBadge;
  final bool canSeeWhoLiked;
  final bool hasHideProfile;

  final int remainingHours;
  final String? endDate;
  final bool isExpiringSoon;
  final bool isExpired;
  final Map<String, dynamic>? expirationAlert;

  // Full features map from backend
  final Map<String, dynamic> features;
  final Map<String, dynamic> usage;

  const PlanStatus({
    this.isActive = false,
    this.tier = 'FREE',
    this.tierRank = 0,
    this.planName = 'Free',
    this.packageId,
    this.remainingDays = 0,
    this.remainingHours = 0,
    this.endDate,
    this.isExpiringSoon = false,
    this.isExpired = false,
    this.expirationAlert,
    this.superlikesRemaining = 0,
    this.superlikesPerCycle = 0,
    this.boostsRemaining = 0,
    this.boostsPerCycle = 0,
    this.dailyLikesLimit = 7,
    this.dailyLikesUsed = 0,
    this.dailyMatchRequestsLimit = 3,
    this.dailyMatchRequestsUsed = 0,
    this.dailyPostsLimit = 5,
    this.dailyPostsUsed = 0,
    this.dailyBacktrackLimit = 3,
    this.dailyBacktrackUsed = 0,
    this.hasPriorityVisibility = false,
    this.hasTrustBadge = false,
    this.hasEliteBadge = false,
    this.canSeeWhoLiked = false,
    this.hasHideProfile = false,
    this.features = const {},
    this.usage = const {},
  });

  // ── Convenience getters ───────────────────────────────────────────────────

  bool get isFree => tier == 'FREE';
  bool get isCore => tier == 'CORE';
  bool get isPlus => tier == 'PLUS';
  bool get isPro => tier == 'PRO';
  bool get isElite => tier == 'ELITE';
  bool get isPaid => tierRank > 0;

  int get dailyLikesLimitInt {
    if (dailyLikesLimit == 'unlimited') return 9999;
    return int.tryParse(dailyLikesLimit.toString()) ?? 7;
  }

  bool get hasUnlimitedLikes => dailyLikesLimit == 'unlimited';
  int get dailyLikesRemaining =>
      hasUnlimitedLikes ? 9999 : (dailyLikesLimitInt - dailyLikesUsed).clamp(0, 9999);

  bool get canSuperLike => superlikesRemaining > 0;
  bool get canBoost => boostsRemaining > 0;

  // ── Tier display helpers ──────────────────────────────────────────────────

  String get tierLabel {
    switch (tier) {
      case 'ELITE': return '👑 Elite';
      case 'PRO':   return '🔮 Pro';
      case 'PLUS':  return '💜 Plus';
      case 'CORE':  return '💙 Core';
      default:      return 'Free';
    }
  }

  /// Hex color for tier ring/badge
  String get tierHexColor {
    switch (tier) {
      case 'ELITE': return '#FFB703';
      case 'PRO':   return '#E100FF';
      case 'PLUS':  return '#7F00FF';
      case 'CORE':  return '#00A9FF';
      default:      return '#9E9E9E';
    }
  }

  // ── Factory ───────────────────────────────────────────────────────────────

  static const PlanStatus free = PlanStatus();

  factory PlanStatus.fromJson(Map<String, dynamic> json) {
    return PlanStatus(
      isActive: json['isActive'] == true,
      tier: json['tier']?.toString() ?? 'FREE',
      tierRank: _parseInt(json['tierRank'], 0),
      planName: json['planName']?.toString() ?? 'Free',
      packageId: json['packageId']?.toString(),
      remainingDays: _parseInt(json['remainingDays'], 0),
      remainingHours: _parseInt(json['remainingHours'], 0),
      endDate: json['endDate']?.toString(),
      isExpiringSoon: json['isExpiringSoon'] == true,
      isExpired: json['isExpired'] == true,
      expirationAlert: json['expirationAlert'] is Map ? Map<String, dynamic>.from(json['expirationAlert']) : null,
      superlikesRemaining: _parseInt(json['superlikesRemaining'], 0),
      superlikesPerCycle: _parseInt(json['superlikesPerCycle'], 0),
      boostsRemaining: _parseInt(json['boostsRemaining'], 0),
      boostsPerCycle: _parseInt(json['boostsPerCycle'], 0),
      dailyLikesLimit: _parseLimit(json['dailyLikesLimit'], 7),
      dailyLikesUsed: _parseInt(json['dailyLikesUsed'], 0),
      dailyMatchRequestsLimit: _parseLimit(json['dailyMatchRequestsLimit'], 3),
      dailyMatchRequestsUsed: _parseInt(json['dailyMatchRequestsUsed'], 0),
      dailyPostsLimit: _parseLimit(json['dailyPostsLimit'], 5),
      dailyPostsUsed: _parseInt(json['dailyPostsUsed'], 0),
      dailyBacktrackLimit: _parseLimit(json['dailyBacktrackLimit'], 3),
      dailyBacktrackUsed: _parseInt(json['dailyBacktrackUsed'], 0),
      hasPriorityVisibility: json['hasPriorityVisibility'] == true,
      hasTrustBadge: json['hasTrustBadge'] == true,
      hasEliteBadge: json['hasEliteBadge'] == true,
      canSeeWhoLiked: json['canSeeWhoLiked'] == true,
      hasHideProfile: json['hasHideProfile'] == true || json['features']?['hide_profile']?['enabled'] == true,
      features: Map<String, dynamic>.from(json['features'] ?? {}),
      usage: Map<String, dynamic>.from(json['usage'] ?? {}),
    );
  }

  static int _parseInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    return int.tryParse(val.toString()) ?? fallback;
  }

  static dynamic _parseLimit(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val == 'unlimited') return 'unlimited';
    return int.tryParse(val.toString()) ?? fallback;
  }
}
