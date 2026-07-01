import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stock_track/app.dart';
import 'package:stock_track/data/providers/repository_providers.dart';
import 'package:stock_track/data/repositories/installation_repository.dart';
import 'package:stock_track/data/repositories/inventory_repository.dart';
import 'package:stock_track/features/dev/chat/services/chat_repository.dart';
import 'package:stock_track/features/dev/report_queue/services/report_repository.dart';
import 'package:stock_track/features/dev/services/harness_auth.dart';
import 'package:stock_track/features/dev/services/harness_providers.dart';

/// Chunk 1 (HARNESS_PARITY_MAP) acceptance — the floating harness entry is mounted
/// at the [MaterialApp.builder] seam, so it floats above EVERY route and can never
/// be covered by a pushed full-screen route. Uses the mock harness trio (no
/// Firebase) so it runs anywhere. On-device keyboard/nav-bar clearance (§7) is
/// verified by the build + on-device dogfood, not by a widget test.
void main() {
  Widget app() => ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(MockInventoryRepository()),
      installationRepositoryProvider.overrideWithValue(
        MockInstallationRepository(),
      ),
      harnessAuthProvider.overrideWithValue(MockHarnessAuth()),
      chatRepositoryProvider.overrideWithValue(MockChatRepository()),
      reportRepositoryProvider.overrideWithValue(MockReportRepository()),
    ],
    child: const StockTrackApp(),
  );

  testWidgets('floating entry is visible on the shell', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.support_agent), findsOneWidget);
  });

  testWidgets('entry floats ABOVE a pushed route (command center)', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Open the command center (pushed into the app Navigator via the navigatorKey).
    await tester.tap(find.byIcon(Icons.support_agent));
    await tester.pumpAndSettle();

    // The command center route is on top…
    expect(find.text('Stock-Track Harness'), findsOneWidget);
    // …and the floating entry is STILL present above it (mounted above the
    // Navigator, not inside a single route) — the core Chunk 1 acceptance.
    expect(find.byIcon(Icons.support_agent), findsOneWidget);
  });
}
