import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stock_track/app.dart';
import 'package:stock_track/data/providers/repository_providers.dart';
import 'package:stock_track/data/repositories/installation_repository.dart';
import 'package:stock_track/data/repositories/inventory_repository.dart';
import 'package:stock_track/features/dev/chat/services/chat_repository.dart';
import 'package:stock_track/features/dev/overlay/harness_tool_button.dart';
import 'package:stock_track/features/dev/overlay/harness_tools.dart';
import 'package:stock_track/features/dev/report_queue/services/report_repository.dart';
import 'package:stock_track/features/dev/voice/harness_voice_button.dart';
import 'package:stock_track/features/dev/services/harness_auth.dart';
import 'package:stock_track/features/dev/services/harness_providers.dart';

/// Overlay CORRECTION acceptance — the floating dev-tools are now a DRAGGABLE
/// MULTI-BUTTON CLUSTER mounted at the [MaterialApp.builder] seam (not a single FAB
/// that pushes a separate command-center page). It floats above EVERY route, and
/// each button launches its tool DIRECTLY over the current screen — the tested
/// screen is never left, and there is no intermediate command-center page in the
/// path. Uses the mock harness trio (no Firebase) so it runs anywhere. Drag /
/// fractional-position persistence / one-at-a-time swap are proven on-device + by
/// the SingleInstanceLauncher unit tests (see harness_test.dart); this widget test
/// proves the cluster SHAPE + direct-launch-over-the-same-screen.
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

  testWidgets('cluster shows MULTIPLE floating tool buttons over the shell', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // The tested shell is still there…
    expect(find.text('Warehouse Dashboard'), findsOneWidget);
    // …with the whole config-driven button set floating directly on top as one
    // draggable cluster (grip handle + one slot per tool spec). Launch-tools render
    // a HarnessToolButton; a STATEFUL builder-tool (the floating mic) renders its own
    // widget instead — so the button count is the launch-tools, and the mic is present.
    final launchTools =
        kHarnessTools.where((s) => s.builder == null).length;
    expect(find.byType(HarnessToolButton), findsNWidgets(launchTools));
    expect(find.byType(HarnessVoiceButton), findsOneWidget); // the floating mic
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget); // the grip handle
  });

  testWidgets(
    'a tool button opens ITS tool over the same screen; cluster floats above',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Tap the Report-queue button → its screen opens DIRECTLY (fullscreenDialog on
      // the root navigator), with NO intermediate command-center page.
      await tester.tap(find.byIcon(Icons.list_alt));
      await tester.pumpAndSettle();

      expect(find.text('Report queue'), findsOneWidget);
      expect(find.text('Stock-Track Harness'), findsNothing); // no menu page
      // …and the cluster STILL floats above the pushed tool (mounted above the
      // Navigator) — its grip handle is present over the tool.
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    },
  );
}
