import 'package:flutter/widgets.dart';

/// Process-wide "what screen is the owner on right now" tracker for the harness.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic: it stores whatever label
/// the app feeds it and names NO project screen itself. The app layer wires the
/// source(s): a [HarnessRouteObserver] on the root Navigator (catches pushed
/// routes) plus, for a tab/IndexedStack shell that isn't route-driven, a direct
/// [update] call from the shell with the current tab label.
///
/// A filed report reads [currentScreen] at capture and stamps it as the report's
/// screen-context ("which screen was I on"), the fastest triage signal. Mirrors the
/// reference harness's route tracker; the value is captured at submit so the report
/// attributes to the screen the owner reported from.
class CurrentScreenTracker {
  const CurrentScreenTracker._();

  /// The last known screen label, or null before anything is tracked.
  static String? currentScreen;

  /// Record the current screen. Null / blank labels are IGNORED (an unnamed route —
  /// e.g. a harness tool pushed without a name — must not clobber the real screen
  /// the owner was last on).
  static void update(String? screen) {
    final s = screen?.trim();
    if (s == null || s.isEmpty) return;
    currentScreen = s;
  }

  /// Test/hygiene hook.
  @visibleForTesting
  static void reset() => currentScreen = null;
}

/// A [NavigatorObserver] that feeds named routes into [CurrentScreenTracker]. Wire
/// it into `MaterialApp.navigatorObservers` (app-agnostic — it only reads
/// `route.settings.name`). Unnamed routes are ignored by [CurrentScreenTracker].
class HarnessRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    CurrentScreenTracker.update(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    CurrentScreenTracker.update(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    CurrentScreenTracker.update(previousRoute?.settings.name);
    super.didPop(route, previousRoute);
  }
}
