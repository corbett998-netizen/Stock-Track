import 'dart:async';

import '../models/installation.dart';
import 'seed_data.dart';

/// The ONLY boundary the UI uses to read/write install records. Same seam as
/// [InventoryRepository]: a `FirebaseInstallationRepository` swaps in later
/// without any UI change.
abstract interface class InstallationRepository {
  /// Live stream of all install records (most relevant first is the UI's job).
  Stream<List<Installation>> watchInstallations();

  /// One-shot read.
  Future<List<Installation>> getInstallations();

  /// Record a new install (written by a scan-out).
  Future<void> add(Installation installation);
}

/// In-memory mock. Seeded from [kSeedInstallations]; backed by a broadcast
/// stream so a scan-out shows up live on the Dashboard. Resets on restart.
class MockInstallationRepository implements InstallationRepository {
  MockInstallationRepository() : _records = List.of(kSeedInstallations);

  final List<Installation> _records;
  final StreamController<List<Installation>> _controller =
      StreamController<List<Installation>>.broadcast();

  List<Installation> get _snapshot => List.unmodifiable(_records);

  @override
  Stream<List<Installation>> watchInstallations() async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Future<List<Installation>> getInstallations() async => _snapshot;

  @override
  Future<void> add(Installation installation) async {
    _records.add(installation);
    _controller.add(_snapshot);
  }
}
