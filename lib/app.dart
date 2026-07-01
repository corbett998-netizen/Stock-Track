import 'package:flutter/material.dart';

import 'core/navigation/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'features/dev/harness_overlay.dart';

/// Root app widget — dark theme + the bottom-nav shell. No auth gate in slice 1
/// (single company, frontend-first); it slots in above [AppShell] later.
///
/// [HarnessOverlay] adds the dev-gated owner/operator harness entry (draggable FAB
/// → command center). In a release build it is inert — the harness never mounts.
class StockTrackApp extends StatelessWidget {
  const StockTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock-Track',
      debugShowCheckedModeBanner: false,
      theme: buildStockTrackTheme(),
      home: const HarnessOverlay(child: AppShell()),
    );
  }
}
