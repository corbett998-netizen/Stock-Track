import 'package:flutter/widgets.dart';

/// Single-instance + mutual-exclusion launcher for the floating dev cluster.
///
/// PART OF THE REUSABLE HARNESS FRAMEWORK — app-agnostic (no project nouns). It
/// backs every tool launch with a tiny keyed open-set so that:
///  - DUPLICATE GUARD: re-tapping the SAME already-open surface is a no-op (no
///    stacked duplicate route/sheet);
///  - EXCLUSIVE GROUP: opening one `exclusive` surface first dismisses whichever
///    OTHER exclusive surface is open, so tools swap cleanly and are never stacked
///    ("one dev surface at a time");
///  - SELF-HEAL: if the open/push throws synchronously the latch is released, so a
///    failed open can never leave a key stuck 'open' (which would block reopen);
///  - the latch clears on the returned future's `whenComplete` no matter how the
///    surface closes (pop, barrier tap, back gesture).
///
/// The cluster lives ABOVE the Navigator at the `MaterialApp.builder` seam, so its
/// own `BuildContext` has no Navigator ancestor — every route push must go through
/// the shared root [navigatorKey]. Set it once at cluster mount. A `fallbackContext`
/// (a standalone widget test that mounts a surface directly) is honoured only when
/// the key is unset.
class SingleInstanceLauncher {
  SingleInstanceLauncher._();

  /// The shared root navigator the cluster pushes tool routes through. Set once by
  /// the cluster at mount (accepts the app's root `navigatorKey` — no app noun here).
  static GlobalKey<NavigatorState>? navigatorKey;

  static final Set<String> _open = <String>{};
  static final Set<String> _exclusive = <String>{};
  static final Map<String, VoidCallback> _dismiss = <String, VoidCallback>{};

  /// Whether a surface registered under [key] is currently open.
  static bool isOpen(String key) => _open.contains(key);

  /// Test/reset hook — clears all latches (never needed in the app).
  @visibleForTesting
  static void resetForTest() {
    _open.clear();
    _exclusive.clear();
    _dismiss.clear();
  }

  static NavigatorState? _resolveNavigator(BuildContext? fallbackContext) {
    final fromKey = navigatorKey?.currentState;
    if (fromKey != null) return fromKey;
    if (fallbackContext != null) {
      return Navigator.maybeOf(fallbackContext, rootNavigator: true);
    }
    return null;
  }

  /// Push [route] under [key] on the root navigator, exactly once.
  ///
  /// Returns the route's pop value (or null when the launch was a no-op — duplicate
  /// or no navigator). When [exclusive], any OTHER open exclusive surface is
  /// dismissed first so the two never stack.
  static Future<T?> pushRoute<T>(
    String key,
    Route<T> route, {
    bool exclusive = false,
    BuildContext? fallbackContext,
  }) {
    if (_open.contains(key)) return Future<T?>.value(null); // duplicate guard
    final nav = _resolveNavigator(fallbackContext);
    if (nav == null) return Future<T?>.value(null);
    if (exclusive) _closeExclusiveExcept(key);

    _open.add(key);
    if (exclusive) _exclusive.add(key);
    _dismiss[key] = () {
      if (nav.mounted && nav.canPop()) nav.pop();
    };

    Future<T?> future;
    try {
      future = nav.push<T>(route);
    } catch (_) {
      _release(key); // self-heal: a synchronous throw must not stick the latch
      rethrow;
    }
    future.whenComplete(() => _release(key));
    return future;
  }

  /// Generic guard for a surface opened by [open] (e.g. `showModalBottomSheet`),
  /// where the caller owns the open call. Same duplicate/exclusive/self-heal
  /// guarantees as [pushRoute]. Provide [dismiss] when the surface is exclusive so
  /// a swap can close it; the latch always clears on the returned future.
  static Future<T?> guard<T>(
    String key,
    Future<T?> Function() open, {
    bool exclusive = false,
    VoidCallback? dismiss,
  }) {
    if (_open.contains(key)) return Future<T?>.value(null); // duplicate guard
    if (exclusive) _closeExclusiveExcept(key);

    _open.add(key);
    if (exclusive) _exclusive.add(key);
    if (dismiss != null) _dismiss[key] = dismiss;

    Future<T?> future;
    try {
      future = open();
    } catch (_) {
      _release(key); // self-heal on synchronous throw
      rethrow;
    }
    future.whenComplete(() => _release(key));
    return future;
  }

  static void _release(String key) {
    _open.remove(key);
    _exclusive.remove(key);
    _dismiss.remove(key);
  }

  /// Dismiss every OTHER open exclusive surface. Snapshot the keys first: a dismiss
  /// can synchronously mutate the open/exclusive sets mid-iteration.
  static void _closeExclusiveExcept(String key) {
    final others = List<String>.of(_exclusive);
    for (final k in others) {
      if (k == key) continue;
      _dismiss[k]?.call();
    }
  }
}
