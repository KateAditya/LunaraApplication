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
import 'api_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final SubscriptionProvider _instance = SubscriptionProvider._();
  static SubscriptionProvider get instance => _instance;
  SubscriptionProvider._();

  // ── State ──────────────────────────────────────────────────────────────────
  PlanStatus _status = PlanStatus.free;
  bool _isLoading = false;
  DateTime? _lastFetched;
  static const _cacheDuration = Duration(minutes: 3);

  PlanStatus get status => _status;
  bool get isLoading => _isLoading;

  // ── Convenience passthrough getters ───────────────────────────────────────
  String get tier => _status.tier;
  int get tierRank => _status.tierRank;
  bool get isFree => _status.isFree;
  bool get isPaid => _status.isPaid;
  int get superlikesRemaining => _status.superlikesRemaining;
  int get boostsRemaining => _status.boostsRemaining;
  int get dailyLikesRemaining => _status.dailyLikesRemaining;
  bool get canSuperLike => _status.canSuperLike;
  bool get canBoost => _status.canBoost;

  // ── Load / Refresh ────────────────────────────────────────────────────────

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
      }
    } catch (e) {
      debugPrint('[SubscriptionProvider] refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load with cache — only fetches if cache is stale or empty.
  Future<void> loadIfNeeded() async {
    if (_lastFetched != null &&
        DateTime.now().difference(_lastFetched!) < _cacheDuration) {
      return; // Still fresh
    }
    await refresh();
  }

  /// Called after a purchase to immediately reflect the new subscription.
  Future<void> refreshAfterPurchase() async {
    // Invalidate cache and force reload
    _lastFetched = null;
    await refresh();
  }

  /// Reset to free state on logout.
  void reset() {
    _status = PlanStatus.free;
    _lastFetched = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Register a socket listener for real-time subscription events.
  void listenToSocket() {
    ApiService.addSocketListener('subscription_updated', _onSubscriptionUpdated);
    ApiService.addSocketListener('subscription_expired', _onSubscriptionExpired);
    ApiService.addSocketListener('boost_activated', _onBoostActivated);
  }

  void stopListeningToSocket() {
    ApiService.removeSocketListener('subscription_updated', _onSubscriptionUpdated);
    ApiService.removeSocketListener('subscription_expired', _onSubscriptionExpired);
    ApiService.removeSocketListener('boost_activated', _onBoostActivated);
  }

  void _onSubscriptionUpdated(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: subscription_updated → refreshing');
    refreshAfterPurchase();
  }

  void _onSubscriptionExpired(dynamic data) {
    debugPrint('[SubscriptionProvider] Socket: subscription_expired → resetting to FREE');
    _status = PlanStatus.free;
    _lastFetched = null;
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
    _provider.loadIfNeeded();
    _provider.listenToSocket();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _provider.stopListeningToSocket();
    super.dispose();
  }

  void _onProviderChanged() => setState(() {});

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
