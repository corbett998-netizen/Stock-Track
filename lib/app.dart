import 'package:flutter/material.dart';

import 'core/navigation/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/current_screen_tracker.dart';
import 'features/dev/dev_gate.dart';
import 'features/dev/overlay/harness_fab_cluster.dart';

/// Root app widget — dark theme + the bottom-nav shell. No auth gate in slice 1
/// (single company, frontend-first); it slots in above [AppShell] later.
///
/// [HarnessFabCluster] adds the dev-gated owner/operator harness — a DRAGGABLE
/// MULTI-BUTTON cluster that floats over the live screen; each button opens its tool
/// (chat, report, queue, ready-to-test, poke, command center) directly over the
/// current screen. In a release build it is inert — the harness never mounts.
///
/// The cluster is mounted at the [MaterialApp.builder] seam (NOT inside `home:`) so
/// it wraps the Navigator's output and floats above EVERY pushed route — it can
/// never be covered by page content or a full-screen route (HARNESS_PARITY_MAP
/// Chunk 1). Because it sits ABOVE the Navigator, every tool launches through the
/// shared [navigatorKey] rather than the (absent) ancestor Navigator of its own
/// context.
class StockTrackApp extends StatelessWidget {
  const StockTrackApp({super.key});

  /// Shared handle to the app Navigator — the overlay lives above it, so it pushes
  /// harness routes via this key.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock-Track',
      debugShowCheckedModeBanner: false,
      theme: buildStockTrackTheme(),
      navigatorKey: navigatorKey,
      // Dev-gated screen-context capture: named routes feed the tracker so a filed
      // report knows "which screen was I on". Inert in a release build.
      navigatorObservers: [if (kHarnessEnabled) HarnessRouteObserver()],
      builder: (context, child) => HarnessFabCluster(
        navigatorKey: navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppShell(),
    );
  }
}
