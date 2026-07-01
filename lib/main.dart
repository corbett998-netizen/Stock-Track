import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/providers/repository_providers.dart';
import 'data/repositories/installation_repository.dart';
import 'data/repositories/inventory_repository.dart';
import 'features/dev/chat/services/chat_repository.dart';
import 'features/dev/dev_gate.dart';
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
