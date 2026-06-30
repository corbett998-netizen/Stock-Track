import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/installation_repository.dart';
import '../repositories/inventory_repository.dart';

/// === THE REPOSITORY SEAM (single swap point) ===
///
/// These providers expose ONLY the abstract repository interfaces. They are
/// intentionally left unimplemented here and MUST be overridden in the root
/// `ProviderScope` (see lib/main.dart). That single override list is the one
/// and only place the app chooses its data source:
///
///   slice 1 (now):   MockInventoryRepository()      / MockInstallationRepository()
///   later (Firebase): FirebaseInventoryRepository() / FirebaseInstallationRepository()
///
/// Because every screen reads these providers (never a concrete class),
/// swapping to Firebase changes ONLY main.dart — no UI/widget edits.
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  throw UnimplementedError(
    'inventoryRepositoryProvider must be overridden in the root ProviderScope '
    '(lib/main.dart). It is the single swap point: Mock now, Firebase later.',
  );
});

final installationRepositoryProvider = Provider<InstallationRepository>((ref) {
  throw UnimplementedError(
    'installationRepositoryProvider must be overridden in the root ProviderScope '
    '(lib/main.dart). It is the single swap point: Mock now, Firebase later.',
  );
});
