// lib/services/optimistic_action_guard.dart
// In-flight action guard to prevent double-clicks/duplicate mutations across Lunara

import 'dart:async';

class OptimisticActionGuard {
  static final Set<String> _inFlightActions = <String>{};

  /// Attempts to acquire an in-flight lock for [actionKey].
  /// Returns `true` if the lock was acquired (first tap).
  /// Returns `false` if the action is already in flight (duplicate tap - ignore).
  static bool start(String actionKey) {
    if (_inFlightActions.contains(actionKey)) {
      return false;
    }
    _inFlightActions.add(actionKey);
    return true;
  }

  /// Releases the in-flight lock for [actionKey].
  static void end(String actionKey) {
    _inFlightActions.remove(actionKey);
  }

  /// Checks if [actionKey] is currently in-flight.
  static bool isInFlight(String actionKey) {
    return _inFlightActions.contains(actionKey);
  }

  /// Alias for isInFlight
  static bool isLocked(String actionKey) => isInFlight(actionKey);

  /// Wraps an async [action] with in-flight protection.
  /// If already in flight, returns `null` immediately.
  static Future<T?> run<T>(String actionKey, Future<T> Function() action) async {
    if (!start(actionKey)) return null;
    try {
      return await action();
    } finally {
      end(actionKey);
    }
  }

  /// Clears all in-flight locks (useful on logout or screen resets).
  static void clear() {
    _inFlightActions.clear();
  }
}
