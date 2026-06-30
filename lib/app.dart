import 'package:flutter/material.dart';

import 'core/navigation/app_shell.dart';
import 'core/theme/app_theme.dart';

/// Root app widget — dark theme + the bottom-nav shell. No auth gate in slice 1
/// (single company, frontend-first); it slots in above [AppShell] later.
class StockTrackApp extends StatelessWidget {
  const StockTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock-Track',
      debugShowCheckedModeBanner: false,
      theme: buildStockTrackTheme(),
      home: const AppShell(),
    );
  }
}
