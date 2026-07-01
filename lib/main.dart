import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/providers/repository_providers.dart';
import 'data/repositories/installation_repository.dart';
import 'data/repositories/inventory_repository.dart';

Future<void> main() async {
  // ===========================================================
  // FIREBASE CORE (Brandon's own project: easy-stock-track).
  //
  // Firebase is now CONNECTED/available (native config from
  // android/app/google-services.json + ios/Runner/GoogleService-Info.plist).
  // Firebase.initializeApp() reads that native config — no firebase_options.dart
  // needed (that requires the FlutterFire CLI authed to Brandon's project).
  //
  // NOTE: this only makes Firebase AVAILABLE. Data STILL comes from the MOCK
  // repositories below — the mock->Firestore data swap is a separate future
  // slice (see docs/MOCKED_VS_REAL.md §4). Never Blueprint Fitness's project.
  // ===========================================================
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(
    ProviderScope(
      // ===========================================================
      // THE SINGLE REPOSITORY SWITCH (data-source seam).
      //
      // Slice 1 (now): in-memory MOCK repositories, seeded with sample
      // inventory + one install record. No Firebase / cloud / backend.
      //
      // Later: replace the two lines below with
      //   inventoryRepositoryProvider.overrideWithValue(FirebaseInventoryRepository())
      //   installationRepositoryProvider.overrideWithValue(FirebaseInstallationRepository())
      // (after adding firebase_core/cloud_firestore + Brandon's own config).
      // Nothing else in the app changes — every screen talks ONLY to the
      // repository interfaces, never to a concrete data source.
      // ===========================================================
      overrides: [
        inventoryRepositoryProvider
            .overrideWithValue(MockInventoryRepository()),
        installationRepositoryProvider
            .overrideWithValue(MockInstallationRepository()),
      ],
      child: const StockTrackApp(),
    ),
  );
}
