// lib/services/subscription_provider.dart
// Centralized subscription state management.
// All screens should listen to this provider instead of making their own API calls.
//
// Usage:
//   final status = SubscriptionProvider.of(context).status;
//   SubscriptionProvider.of(context).refresh();
//
// Or listen for changes:
//   context.dependOnInheritedWidgetOfExactType<SubscriptionInheritedWidget>();

import 'package:flutter/material.dart';
import '../models/plan_status.dart';
import '../models/vip_entitlement_model.dart';
import '../widgets/vip_expiration_dialog.dart';
import 'api_service.dart';
import 'notification_navigator.dart';
import 'realtime_sync_manager.dart';

enum VipAction {
  like,
  superlike,
  boost,
  partyPlan,
  backtrack,
  matchRequest,
}

class VipActionValidation {
  final bool allowed;
  final VipAction action;
  final String? message;
  final String? code;
  final dynamic limit;
  final dynamic remaining;
  final bool isUnlimited;

  const VipActionValidation({
    required this.allowed,
    required this.action,
    this.message,
    this.code,
    this.limit,
    this.remaining,
    this.isUnlimited = false,
  });
}

enum VipFeature {
  hideProfile,
  priorityVisibility,
  trustBadge,
  seeWhoLikedMe,
  seeWhoViewedMe,
  partyCreation,
  strangerMeet,
}

class SubscriptionProvider extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final SubscriptionProvider _instance = SubscriptionProvider._();
  static SubscriptionProvider get instance => _instance;
  SubscriptionProvider._() {
    RealtimeSyncManager.instance.vipStatusNotifier.addListener(_onVipRealtimeEvent);
  }

  void _onVipRealtimeEvent() {
    final event = RealtimeSyncManager.instance.vipStatusNotifier.value;
    if (event != null) {
      refresh();
      fetchEntitlementsSummary();
    }
  }

  // ── State ──────────────────────────────────────────────────────────────────
  PlanStatus _status = PlanStatus.free;
  EntitlementsSummaryModel? _entitlementsSummary;
  List<SubscriptionAddonPackageModel> _availableAddons = [];
  bool _isLoading = false;
  bool _isLoadingEntitlements = false;
  bool _isLoadingAddons = false;
  DateTime? _lastFetched;
  static const _cacheDuration = Duration(minutes: 3);

  int _optimisticLikesOffset = 0;
  int _optimisticSuperlikesOffset = 0;
  int _optimisticBoostsOffset = 0;
  int _optimisticBacktracksOffset = 0;

  PlanStatus get status => _status;
  EntitlementsSummaryModel? get entitlementsSummary => _entitlementsSummary;
  List<SubscriptionAddonPackageModel> get availableAddons => _availableAddons;
  bool get isLoading => _isLoading;
  bool get isLoadingEntitlements => _isLoadingEntitlements;
  bool get isLoadingAddons => _isLoadingAddons;

  // ── Convenience passthrough getters ───────────────────────────────────────
  String get tier => _status.tier;
  int get tierRank => _status.tierRank;
  bool get isFree => _status.isFree;
  bool get isPaid => _status.isPaid;
  bool get isElite => _status.isElite;

  int get superlikesRemaining => (isElite || _status.isUnlimitedSuperlikes)
      ? 9999
      : (((_entitlementsSummary != null && _entitlementsSummary!.superlikesAvailable > 0)
              ? _entitlementsSummary!.superlikesAvailable
              : _status.superlikesRemaining) - _optimisticSuperlikesOffset).clamp(0, 9999);

  int get boostsRemaining => (isElite || _status.isUnlimitedBoosts)
      ? 9999
      : (((_entitlementsSummary != null && _entitlementsSummary!.boostsAvailable > 0)
              ? _entitlementsSummary!.boostsAvailable
              : _status.boostsRemaining) - _optimisticBoostsOffset).clamp(0, 9999);

  bool get hasUnlimitedLikes => _status.hasUnlimitedLikes;
  int get likesRemaining => dailyLikesRemaining;

  int get dailyLikesRemaining => _status.hasUnlimitedLikes
      ? 9999
      : (_status.dailyLikesRemaining - _optimisticLikesOffset).clamp(0, 9999);

  int get dailyBacktrackRemaining => _status.hasUnlimitedBacktracks
      ? 9999
      : (_status.dailyBacktrackRemaining - _optimisticBacktracksOffset).clamp(0, 9999);

  bool get canLike => _status.hasUnlimitedLikes || dailyLikesRemaining > 0;
  bool get canSuperLike => isElite || _status.isUnlimitedSuperlikes || superlikesRemaining > 0;
  bool get canBoost => isElite || _status.isUnlimitedBoosts || boostsRemaining > 0;
  bool get canBacktrack => _status.hasUnlimitedBacktracks || dailyBacktrackRemaining > 0;
  bool get canCreatePartyPlan => true;

  // ── Optimistic State Modifiers ───────────────────────────────────────────

  void optimisticConsume(VipAction action) {
    if (isElite || _status.isElite) return;
    switch (action) {
      case VipAction.like:
        if (!_status.hasUnlimitedLikes) {
          _optimisticLikesOffset++;
          notifyListeners();
        }
        break;
      case VipAction.superlike:
        if (!_status.isUnlimitedSuperlikes) {
          _optimisticSuperlikesOffset++;
          notifyListeners();
        }
        break;
      case VipAction.boost:
        if (!_status.isUnlimitedBoosts) {
          _optimisticBoostsOffset++;
          notifyListeners();
        }
        break;
      case VipAction.backtrack:
        if (!_status.hasUnlimitedBacktracks) {
          _optimisticBacktracksOffset++;
          notifyListeners();
        }
        break;
      default:
        break;
    }
  }

  void rollbackConsume(VipAction action) {
    if (isElite || _status.isElite) return;
    switch (action) {
      case VipAction.like:
        if (_optimisticLikesOffset > 0) {
          _optimisticLikesOffset--;
          notifyListeners();
        }
        break;
      case VipAction.superlike:
        if (_optimisticSuperlikesOffset > 0) {
          _optimisticSuperlikesOffset--;
          notifyListeners();
        }
        break;
      case VipAction.boost:
        if (_optimisticBoostsOffset > 0) {
          _optimisticBoostsOffset--;
          notifyListeners();
        }
        break;
      case VipAction.backtrack:
        if (_optimisticBacktracksOffset > 0) {
          _optimisticBacktracksOffset--;
          notifyListeners();
        }
        break;
      default:
        break;
    }
  }

  /// O(1) in-memory synchronous Quota Validation
  VipActionValidation validateAction(VipAction action) {
    if (isElite || _status.isElite) {
      return VipActionValidation(
        allowed: true,
        action: action,
        isUnlimited: true,
        limit: 'unlimited',
        remaining: 'unlimited',
      );
    }

    switch (action) {
      case VipAction.like:
        if (_status.hasUnlimitedLikes) {
          return const VipActionValidation(
            allowed: true,
            action: VipAction.like,
            isUnlimited: true,
            limit: 'unlimited',
            remaining: 'unlimited',
          );
        }
        final rem = dailyLikesRemaining;
        if (rem <= 0) {
          return VipActionValidation(
            allowed: false,
            action: VipAction.like,
            code: 'DAILY_LIKES_LIMIT_REACHED',
            limit: _status.dailyLikesLimitInt,
            remaining: 0,
            message: "You've used all your daily likes (${_status.dailyLikesLimitInt}/${_status.dailyLikesLimitInt}). Upgrade your plan to get more likes!",
          );
        }
        return VipActionValidation(
          allowed: true,
          action: VipAction.like,
          limit: _status.dailyLikesLimitInt,
          remaining: rem,
        );

      case VipAction.superlike:
        if (isElite || _status.isUnlimitedSuperlikes || superlikesRemaining >= 9999) {
          return const VipActionValidation(
            allowed: true,
            action: VipAction.superlike,
            isUnlimited: true,
            limit: 'unlimited',
            remaining: 'unlimited',
          );
        }
        final rem = superlikesRemaining;
        if (rem <= 0) {
          return VipActionValidation(
            allowed: false,
            action: VipAction.superlike,
            code: 'SUPERLIKE_LIMIT_REACHED',
            limit: 0,
            remaining: 0,
            message: isPaid
                ? "You've used all your Super Likes for this cycle. Top up with an Add-on pack!"
                : "You don't have any Super Likes remaining. Upgrade to VIP or get an Add-on pack!",
          );
        }
        return VipActionValidation(
          allowed: true,
          action: VipAction.superlike,
          limit: rem,
          remaining: rem,
        );

      case VipAction.boost:
        if (isElite || _status.isUnlimitedBoosts || boostsRemaining >= 9999) {
          return const VipActionValidation(
            allowed: true,
            action: VipAction.boost,
            isUnlimited: true,
            limit: 'unlimited',
            remaining: 'unlimited',
          );
        }
        final rem = boostsRemaining;
        if (rem <= 0) {
          return VipActionValidation(
            allowed: false,
            action: VipAction.boost,
            code: 'BOOST_LIMIT_REACHED',
            limit: 0,
            remaining: 0,
            message: isPaid
                ? "You've used all your Profile Boosts for this cycle. Purchase a Boost pack to get spotlighted!"
                : "Profile Boosts are a VIP feature. Upgrade your plan or purchase a Boost pack!",
          );
        }
        return VipActionValidation(
          allowed: true,
          action: VipAction.boost,
          limit: rem,
          remaining: rem,
        );

      case VipAction.backtrack:
        final rem = dailyBacktrackRemaining;
        if (rem <= 0 && !_status.hasUnlimitedBacktracks) {
          return VipActionValidation(
            allowed: false,
            action: VipAction.backtrack,
            code: 'BACKTRACK_LIMIT_REACHED',
            limit: _status.dailyBacktrackLimitInt,
            remaining: 0,
            message: "You've used all your backtracks for today. Upgrade to VIP for more!",
          );
        }
        return VipActionValidation(
          allowed: true,
          action: VipAction.backtrack,
          isUnlimited: _status.hasUnlimitedBacktracks,
          limit: _status.dailyBacktrackLimitInt,
          remaining: rem,
        );

      case VipAction.partyPlan:
        return VipActionValidation(
          allowed: true,
          action: VipAction.partyPlan,
          isUnlimited: isElite,
          limit: isElite ? 'unlimited' : (_status.isPaid ? 3 : 1),
          remaining: isElite ? 'unlimited' : 1,
        );

      case VipAction.matchRequest:
        if (_status.isPaid || _status.dailyMatchRequestsLimit == 'unlimited') {
          return const VipActionValidation(
            allowed: true,
            action: VipAction.matchRequest,
            isUnlimited: true,
            limit: 'unlimited',
            remaining: 'unlimited',
          );
        }
        final rem = (_status.dailyMatchRequestsLimitInt - _status.dailyMatchRequestsUsed).clamp(0, 9999);
        return VipActionValidation(
          allowed: rem > 0,
          action: VipAction.matchRequest,
          limit: _status.dailyMatchRequestsLimit,
          remaining: rem,
        );
    }
  }

  String? _lastShownAlertKey;

  // ── Load / Refresh ────────────────────────────────────────────────────────

  /// Check and dispatch expiration popup alert if present in PlanStatus
  void _checkAndDispatchExpirationAlert() {
    final alert = _status.expirationAlert;
    if (alert != null && alert.isNotEmpty) {
      final eventType = alert['eventType']?.toString() ?? 'vip_expiring';
      final remainingHours = alert['remainingHours']?.toString() ?? '0';
      final isExpired = alert['isExpired'] == true;
      final alertKey = '${eventType}_${remainingHours}_${isExpired ? "exp" : "act"}_${DateTime.now().day}';

      if (_lastShownAlertKey != alertKey) {
        _lastShownAlertKey = alertKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onShowExpirationAlert?.call(alert);
        });
      }
    }
  }

  /// Force-refresh from backend (bypasses cache).
  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.fetchSubscriptionStatus();
      if (data.isNotEmpty) {
        _status = PlanStatus.fromJson(data);
        _lastFetched = DateTime.now();
        _optimisticLikesOffset = 0;
        _optimisticSuperlikesOffset = 0;
        _optimisticBoostsOffset = 0;
        _optimisticBacktracksOffset = 0;
        _checkAndDispatchExpirationAlert();
      }
    } catch (e) {
      debugPrint('[SubscriptionProvider] refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches the full breakdown of plan entitlements, usage, and separated add-on balances.
  Future<void> fetchEntitlementsSummary({bool force = false}) async {
    if (_isLoadingEntitlements && !force) return;
    _isLoadingEntitlements = true;
    notifyListeners();
    try {
      final data = await ApiService.fetchEntitlementsSummary();
      if (data.isNotEmpty) {
        _entitlementsSummary = EntitlementsSummaryModel.fromJson(data);
        _optimisticSuperlikesOffset = 0;
        _optimisticBoostsOffset = 0;
      }
    } catch (e) {
      debugPrint('[SubscriptionProvider] fetchEntitlementsSummary error: $e');
    } finally {
      _isLoadingEntitlements = false;
      notifyListeners();
    }
  }

  /// Fetches available Add-on packs catalog.
  Future<void> fetchAvailableAddons() async {
    if (_isLoadingAddons) return;
    _isLoadingAddons = true;
    notifyListeners();
    try {
      final list = await ApiService.fetchAvailableAddons();
      _availableAddons = list.map((e) => SubscriptionAddonPackageModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[SubscriptionProvider] fetchAvailableAddons error: $e');
    } finally {
      _isLoadingAddons = false;
      notifyListeners();
    }
  }

  /// Purchases an Add-on package using Smart Credit Wallet.
  Future<Map<String, dynamic>> purchaseAddonWithWallet(String addonPackageId, {int count = 1}) async {
    final result = await ApiService.purchaseAddonWithWallet(addonPackageId, count: count);
    if (result['success'] == true) {
      await refresh();
      await fetchEntitlementsSummary(force: true);
    }
    return result;
  }

  /// Load with cache — only fetches if cache is stale or empty.
  Future<void> loadIfNeeded() async {
    if (_lastFetched != null &&
        DateTime.now().difference(_lastFetched!) < _cacheDuration) {
      return; // Still fresh
    }
    await refresh();
    await fetchEntitlementsSummary();
    await fetchAvailableAddons();
  }

  /// Called after a purchase to immediately reflect the new subscription.
  Future<void> refreshAfterPurchase() async {
    // Invalidate cache and force reload
    _lastFetched = null;
    _lastShownAlertKey = null;
    await refresh();
    await fetchEntitlementsSummary(force: true);
  }

  /// Reset to free state on logout.
  void reset() {
    _status = PlanStatus.free;
    _entitlementsSummary = null;
    _availableAddons = [];
    _lastFetched = null;
    _lastShownAlertKey = null;
    _isLoading = false;
    _isLoadingEntitlements = false;
    _isLoadingAddons = false;
    notifyListeners();
  }

  // ── Expiration Alert Callback ───────────────────────────────────────────
  void Function(Map<String, dynamic> data)? onShowExpirationAlert;

  /// Register a socket listener for real-time subscription events.
  void listenToSocket() {
    ApiService.addSocketListener('subscription_updated', _onSubscriptionUpdated);
    ApiService.addSocketListener('subscription_expiring', _onSubscriptionExpiring);
    ApiService.addSocketListener('subscription_expired', _onSubscriptionExpired);
    ApiService.addSocketListener('boost_activated', _onBoostActivated);
    ApiService.addSocketListener('boost_expired', _onBoostExpired);
    ApiService.addSocketListener('like_received', _onLikeReceived);
    ApiService.addSocketListener('superlike_received', _onSuperlikeReceived);
    ApiService.addSocketListener('like_removed', _onLikeRemoved);
  }

  void stopListeningToSocket() {
    ApiService.removeSocketListener('subscription_updated', _onSubscriptionUpdated);
    ApiService.removeSocketListener('subscription_expiring', _onSubscriptionExpiring);
    ApiService.removeSocketListener('subscription_expired', _onSubscriptionExpired);
    ApiService.removeSocketListener('boost_activated', _onBoostActivated);
    ApiService.removeSocketListener('boost_expired', _onBoostExpired);
    ApiService.removeSocketListener('like_received', _onLikeReceived);
    ApiService.removeSocketListener('superlike_received', _onSuperlikeReceived);
    ApiService.removeSocketListener('like_removed', _onLikeRemoved);
  }

  void _onLikeReceived(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: like_received → refreshing status & badge counts');
    refresh();
  }

  void _onSuperlikeReceived(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: superlike_received → refreshing status & badge counts');
    refresh();
  }

  void _onLikeRemoved(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: like_removed → refreshing status & badge counts');
    refresh();
  }

  void _onBoostExpired(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: boost_expired → refreshing');
    refresh();
  }

  void _onSubscriptionUpdated(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: subscription_updated → refreshing');
    refreshAfterPurchase();
  }

  void _onSubscriptionExpiring(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: subscription_expiring → $data');
    if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      onShowExpirationAlert?.call(mapData);
    }
    refresh();
  }

  void _onSubscriptionExpired(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: subscription_expired → resetting to FREE');
    _status = PlanStatus.free;
    _lastFetched = null;
    if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      onShowExpirationAlert?.call(mapData);
    }
    notifyListeners();
  }

  void _onBoostActivated(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: boost_activated → refreshing');
    refresh();
  }

  // ── Feature helpers ───────────────────────────────────────────────────────

  bool isFeatureEnabled(String key) {
    final feat = _status.features[key];
    if (feat == null) return false;
    return feat['enabled'] == true;
  }

  dynamic getFeatureLimit(String key) {
    final feat = _status.features[key];
    if (feat == null) return 0;
    return feat['limit'];
  }

  /// Centralized VIP Feature entitlement check.
  /// Returns true only if the subscription is active and the specific feature is granted.
  bool hasVipFeature(VipFeature feature) {
    if (!_status.isActive) return false;

    switch (feature) {
      case VipFeature.hideProfile:
        // Hide profile is available to PLUS, PRO, and ELITE, or when hasHideProfile / dynamic feature flag is active
        return _status.hasHideProfile || _status.isPlus || _status.isPro || _status.isElite || isFeatureEnabled('hide_profile');
      case VipFeature.priorityVisibility:
        return _status.hasPriorityVisibility;
      case VipFeature.trustBadge:
        return _status.hasTrustBadge;
      case VipFeature.seeWhoLikedMe:
      case VipFeature.seeWhoViewedMe:
        return _status.canSeeWhoLiked;
      case VipFeature.partyCreation:
        return isFeatureEnabled('party_creation');
      case VipFeature.strangerMeet:
        return isFeatureEnabled('stranger_meet');
    }
  }
}

// ── InheritedWidget wrapper for widget-tree access ─────────────────────────

class SubscriptionScope extends StatefulWidget {
  final Widget child;
  const SubscriptionScope({super.key, required this.child});

  @override
  State<SubscriptionScope> createState() => _SubscriptionScopeState();

  static SubscriptionProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SubscriptionInheritedWidget>();
    assert(scope != null, 'SubscriptionScope not found in widget tree');
    return scope!.provider;
  }

  /// Non-rebuilding access — use when you just need the current value, not reactivity.
  static SubscriptionProvider read(BuildContext context) {
    return SubscriptionProvider.instance;
  }
}

class _SubscriptionScopeState extends State<SubscriptionScope> {
  final _provider = SubscriptionProvider.instance;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
    _provider.onShowExpirationAlert = _handleShowExpirationAlert;
    _provider.loadIfNeeded();
    _provider.listenToSocket();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _provider.onShowExpirationAlert = null;
    _provider.stopListeningToSocket();
    super.dispose();
  }

  void _onProviderChanged() => setState(() {});

  void _handleShowExpirationAlert(Map<String, dynamic> data) {
    final navContext = NotificationNavigator.navigatorKey.currentContext;
    if (navContext == null) return;

    final title = data['title']?.toString() ?? 'VIP Subscription Alert';
    final body = data['body']?.toString() ?? (data['message']?.toString() ?? 'Your VIP subscription status has changed.');
    final planName = data['planName']?.toString() ?? 'VIP Membership';
    final remainingHours = (data['remainingHours'] is num)
        ? (data['remainingHours'] as num).toInt()
        : (int.tryParse(data['remainingHours']?.toString() ?? '0') ?? 0);
    final isExpired = data['isExpired'] == true || data['eventType'] == 'vip_expired';

    VipExpirationDialog.show(
      navContext,
      title: title,
      message: body,
      planName: planName,
      remainingHours: remainingHours,
      isExpired: isExpired,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SubscriptionInheritedWidget(
      provider: _provider,
      child: widget.child,
    );
  }
}

class _SubscriptionInheritedWidget extends InheritedWidget {
  final SubscriptionProvider provider;
  const _SubscriptionInheritedWidget({
    required this.provider,
    required super.child,
  });

  @override
  bool updateShouldNotify(_SubscriptionInheritedWidget oldWidget) => true;
}
