import 'package:flutter/material.dart';

/// Holds a global navigator key so push notification taps can trigger
/// navigation even without a BuildContext (e.g. from background handlers).
class NotificationNavigator {
  NotificationNavigator._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Convenience getter for the current navigator state.
  static NavigatorState? get navigator => navigatorKey.currentState;
}
