import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/providers/repository_providers.dart';
import 'data/repositories/installation_repository.dart';
import 'data/repositories/inventory_repository.dart';

void main() {
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
