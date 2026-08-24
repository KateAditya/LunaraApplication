// lib/models/vip_entitlement_model.dart
// VIP Entitlements, Usage Progress, Add-on Balances, and Add-on Marketplace Models

class PlanEntitlementItem {
  final String featureKey;
  final String name;
  final String icon;
  final int includedQuantity;
  final int usedQuantity;
  final int remainingQuantity;
  final int progressPercentage;
  final bool isUnlimited;
  final String unit;
  final bool isLow;

  const PlanEntitlementItem({
    required this.featureKey,
    required this.name,
    required this.icon,
    required this.includedQuantity,
    required this.usedQuantity,
    required this.remainingQuantity,
    required this.progressPercentage,
    required this.isUnlimited,
    required this.unit,
    this.isLow = false,
  });

  factory PlanEntitlementItem.fromJson(Map<String, dynamic> json) {
    return PlanEntitlementItem(
      featureKey: json['featureKey']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '✨',
      includedQuantity: _parseInt(json['includedQuantity'], 0),
      usedQuantity: _parseInt(json['usedQuantity'], 0),
      remainingQuantity: _parseInt(json['remainingQuantity'], 0),
      progressPercentage: _parseInt(json['progressPercentage'], 0),
      isUnlimited: json['isUnlimited'] == true,
      unit: json['unit']?.toString() ?? '',
      isLow: json['isLow'] == true,
    );
  }

  static int _parseInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }
}

class IncludedChecklistItem {
  final String name;
  final String description;
  final bool isEnabled;
  final String icon;

  const IncludedChecklistItem({
    required this.name,
    required this.description,
    required this.isEnabled,
    required this.icon,
  });

  factory IncludedChecklistItem.fromJson(Map<String, dynamic> json) {
    return IncludedChecklistItem(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      isEnabled: json['isEnabled'] == true,
      icon: json['icon']?.toString() ?? '✨',
    );
  }
}

class AddonBalanceItem {
  final String? id;
  final String featureKey;
  final String name;
  final int purchasedQuantity;
  final int usedQuantity;
  final int remainingQuantity;

  const AddonBalanceItem({
    this.id,
    required this.featureKey,
    required this.name,
    required this.purchasedQuantity,
    required this.usedQuantity,
    required this.remainingQuantity,
  });

  factory AddonBalanceItem.fromJson(Map<String, dynamic> json) {
    return AddonBalanceItem(
      id: json['id']?.toString(),
      featureKey: json['featureKey']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      purchasedQuantity: _parseInt(json['purchasedQuantity'], 0),
      usedQuantity: _parseInt(json['usedQuantity'], 0),
      remainingQuantity: _parseInt(json['remainingQuantity'], 0),
    );
  }

  static int _parseInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }
}

class SubscriptionAddonPackageModel {
  final String id;
  final String name;
  final String featureKey;
  final int quantity;
  final double price;
  final String currency;
  final bool isActive;
  final String? badge;
  final String? description;
  final int displayOrder;

  const SubscriptionAddonPackageModel({
    required this.id,
    required this.name,
    required this.featureKey,
    required this.quantity,
    required this.price,
    this.currency = 'INR',
    this.isActive = true,
    this.badge,
    this.description,
    this.displayOrder = 0,
  });

  factory SubscriptionAddonPackageModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionAddonPackageModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      featureKey: json['featureKey']?.toString() ?? '',
      quantity: _parseInt(json['quantity'], 1),
      price: _parseDouble(json['price'], 0.0),
      currency: json['currency']?.toString() ?? 'INR',
      isActive: json['isActive'] != false,
      badge: json['badge']?.toString(),
      description: json['description']?.toString(),
      displayOrder: _parseInt(json['displayOrder'], 0),
    );
  }

  static int _parseInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double _parseDouble(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }
}

class SmartSuggestionItem {
  final String featureKey;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String? addonPackageId;

  const SmartSuggestionItem({
    required this.featureKey,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.addonPackageId,
  });

  factory SmartSuggestionItem.fromJson(Map<String, dynamic> json) {
    return SmartSuggestionItem(
      featureKey: json['featureKey']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      actionLabel: json['actionLabel']?.toString() ?? 'Get Add-on',
      addonPackageId: json['addonPackageId']?.toString(),
    );
  }
}

class EntitlementsSummaryModel {
  final String planTier;
  final String planName;
  final bool isActive;
  final bool isExpired;
  final int remainingDays;
  final int remainingHours;
  final String? endDate;
  final List<PlanEntitlementItem> planBenefits;
  final List<IncludedChecklistItem> includedFeaturesChecklist;
  final List<AddonBalanceItem> activeAddons;
  final Map<String, dynamic> totals;
  final List<SmartSuggestionItem> smartSuggestions;

  const EntitlementsSummaryModel({
    this.planTier = 'FREE',
    this.planName = 'Free Tier',
    this.isActive = false,
    this.isExpired = false,
    this.remainingDays = 0,
    this.remainingHours = 0,
    this.endDate,
    this.planBenefits = const [],
    this.includedFeaturesChecklist = const [],
    this.activeAddons = const [],
    this.totals = const {},
    this.smartSuggestions = const [],
  });

  int get superlikesAvailable {
    final val = totals['superlikesAvailable'];
    if (val is int) return val;
    return int.tryParse(val?.toString() ?? '0') ?? 0;
  }

  int get boostsAvailable {
    final val = totals['boostsAvailable'];
    if (val is int) return val;
    return int.tryParse(val?.toString() ?? '0') ?? 0;
  }

  dynamic get partyPlansAvailable => totals['partyPlansAvailable'] ?? 0;
  dynamic get likesAvailable => totals['likesAvailable'] ?? 7;

  factory EntitlementsSummaryModel.fromJson(Map<String, dynamic> json) {
    return EntitlementsSummaryModel(
      planTier: json['planTier']?.toString() ?? 'FREE',
      planName: json['planName']?.toString() ?? 'Free Tier',
      isActive: json['isActive'] == true,
      isExpired: json['isExpired'] == true,
      remainingDays: _parseInt(json['remainingDays'], 0),
      remainingHours: _parseInt(json['remainingHours'], 0),
      endDate: json['endDate']?.toString(),
      planBenefits: (json['planBenefits'] as List<dynamic>?)
              ?.map((e) => PlanEntitlementItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      includedFeaturesChecklist: (json['includedFeaturesChecklist'] as List<dynamic>?)
              ?.map((e) => IncludedChecklistItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      activeAddons: (json['activeAddons'] as List<dynamic>?)
              ?.map((e) => AddonBalanceItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      totals: json['totals'] is Map ? Map<String, dynamic>.from(json['totals']) : {},
      smartSuggestions: (json['smartSuggestions'] as List<dynamic>?)
              ?.map((e) => SmartSuggestionItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }

  static int _parseInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }
}
