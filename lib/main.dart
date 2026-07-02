import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/providers/repository_providers.dart';
import 'data/repositories/installation_repository.dart';
import 'data/repositories/inventory_repository.dart';
import 'features/dev/chat/screens/orchestrator_chat_screen.dart';
import 'features/dev/chat/services/chat_repository.dart';
import 'features/dev/dev_gate.dart';
import 'features/dev/overlay/single_instance_launcher.dart';
import 'features/dev/push/harness_push_service.dart';
import 'features/dev/report_queue/services/report_repository.dart';
import 'features/dev/services/harness_auth.dart';
import 'features/dev/services/harness_local_store.dart';
import 'features/dev/services/harness_providers.dart';
import 'harness/harness_config.g.dart';

Future<void> main() async {
  // ===========================================================
  // FIREBASE CORE (Brandon's own project: easy-stock-track).
  //
  // Firebase is CONNECTED/available (native config from
  // android/app/google-services.json + ios/Runner/GoogleService-Info.plist).
  // Firebase.initializeApp() reads that native config — no firebase_options.dart
  // needed. Never Blueprint Fitness's project.
  //
  // INVENTORY data still comes from the MOCK repositories below (mock->Firestore
  // swap is a separate future slice). The OWNER/OPERATOR HARNESS (chat + reports)
  // is the surface that persists to easy-stock-track, via the harness seam below.
  // ===========================================================
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Resolve the harness trio for the chosen mode. Only mock mode opens the durable
  // local store (so the mock/local path survives restart); the firebase path is
  // untouched — Firestore already persists server-side.
  final harnessOverrides = await _harnessOverrides();

  // Push-notification parity: wire the FCM handlers (background handler must be
  // registered before runApp). App-specific seam — see _wireHarnessPush.
  await _wireHarnessPush();

  runApp(
    ProviderScope(
      // ===========================================================
      // THE REPOSITORY SWITCHES (data-source seams).
      //
      // Inventory: in-memory MOCK (unchanged — frontend-first, no real-DB swap).
      //
      // Harness: the ported owner/operator harness (chat + report flow + queue).
      // ONE constant `kHarnessMode` (features/dev/dev_gate.dart) picks the trio:
      //   HarnessMode.firebase → persists to easy-stock-track (the owner proof)
      //   HarnessMode.mock     → seeded in-memory, zero backend dependency (demo)
      // Every harness widget talks ONLY to the abstract interfaces, so the mode
      // is chosen HERE and nowhere else.
      // ===========================================================
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(MockInventoryRepository()),
        installationRepositoryProvider
            .overrideWithValue(MockInstallationRepository()),
        ...harnessOverrides,
      ],
      child: const StockTrackApp(),
    ),
  );
}

/// Wire the reusable harness PUSH capability (ported parity feature).
///
/// This is the ONE app-specific push seam — the framework push service
/// ([HarnessPushService]) is app-agnostic and takes an injected "open the chat surface"
/// action, which is the only place a concrete screen/route is named. Push is harness
/// infra, so it is gated to dev builds ([kHarnessEnabled]) + firebase mode (mock has no
/// backend to push from). Fully guarded — never blocks launch.
Future<void> _wireHarnessPush() async {
  if (!kHarnessEnabled || kHarnessMode != HarnessMode.firebase) return;
  // Deep-link target: open the SAME orchestrator-chat surface the cluster tool opens,
  // under the SAME launcher key so a repeat tap is a no-op (never a stacked duplicate).
  HarnessPushService.instance.openChatSurface = (uid) {
    SingleInstanceLauncher.pushRoute<void>(
      'orchestrator_chat',
      MaterialPageRoute<void>(
        builder: (_) => OrchestratorChatScreen(uid: uid),
        fullscreenDialog: true,
      ),
      exclusive: true,
    );
  };
  await HarnessPushService.instance.init();
}

/// The harness trio, selected by [kHarnessMode].
///
/// firebase: unchanged — no store, no extra awaits (Firestore is the durable store).
/// mock: opens a durable [HarnessLocalStore] (namespaced from config) and threads it
/// into the mock chat + report repos so chat, reports, the queue, and the derived
/// dogfood/ready-to-test state survive an app restart.
Future<List<Override>> _harnessOverrides() async {
  switch (kHarnessMode) {
    case HarnessMode.firebase:
      return [
        harnessAuthProvider.overrideWithValue(FirebaseHarnessAuth()),
        chatRepositoryProvider.overrideWithValue(FirebaseChatRepository()),
        reportRepositoryProvider.overrideWithValue(FirebaseReportRepository()),
      ];
    case HarnessMode.mock:
      // Namespace the store per-app from config (never a literal here) so a
      // multi-app install can never collide.
      final store = await SharedPrefsHarnessLocalStore.create(
        namespace: 'harness_${HarnessConfig.projectName}',
        collections: const [HarnessStoreKeys.chat, HarnessStoreKeys.reports],
      );
      return [
        harnessAuthProvider.overrideWithValue(MockHarnessAuth()),
        chatRepositoryProvider.overrideWithValue(MockChatRepository(store)),
        reportRepositoryProvider.overrideWithValue(MockReportRepository(store)),
      ];
  }
}
