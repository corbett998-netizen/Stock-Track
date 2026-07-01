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
import 'features/dev/services/harness_providers.dart';

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
        ..._harnessOverrides(),
      ],
      child: const StockTrackApp(),
    ),
  );
}

/// The harness trio, selected by [kHarnessMode].
List<Override> _harnessOverrides() {
  switch (kHarnessMode) {
    case HarnessMode.firebase:
      return [
        harnessAuthProvider.overrideWithValue(FirebaseHarnessAuth()),
        chatRepositoryProvider.overrideWithValue(FirebaseChatRepository()),
        reportRepositoryProvider.overrideWithValue(FirebaseReportRepository()),
      ];
    case HarnessMode.mock:
      return [
        harnessAuthProvider.overrideWithValue(MockHarnessAuth()),
        chatRepositoryProvider.overrideWithValue(MockChatRepository()),
        reportRepositoryProvider.overrideWithValue(MockReportRepository()),
      ];
  }
}
