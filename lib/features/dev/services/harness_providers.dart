import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/services/chat_repository.dart';
import '../report_queue/models/report.dart';
import '../report_queue/services/report_repository.dart';
import 'harness_auth.dart';

/// === THE HARNESS SEAM (single swap point, mirrors the inventory seam) ===
///
/// These three providers expose ONLY the abstract harness interfaces and are
/// overridden in the root `ProviderScope` (lib/main.dart) with either the Firebase
/// trio (persists to easy-stock-track — "Rung 1") or the Mock trio (seeded
/// in-memory — "Rung 0"), driven by the single `kHarnessMode` constant. No harness
/// widget ever names a concrete data source, so switching modes touches only
/// main.dart.
final harnessAuthProvider = Provider<HarnessAuth>((ref) {
  throw UnimplementedError(
    'harnessAuthProvider must be overridden in the root ProviderScope (lib/main.dart).',
  );
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  throw UnimplementedError(
    'chatRepositoryProvider must be overridden in the root ProviderScope (lib/main.dart).',
  );
});

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  throw UnimplementedError(
    'reportRepositoryProvider must be overridden in the root ProviderScope (lib/main.dart).',
  );
});

/// The owner UID for this session — anonymous-Auth uid (Firebase) or the mock uid.
/// A [FutureProvider] because Firebase sign-in is async and can fail (backend not
/// enabled yet); the harness surfaces render its loading / error / data states so
/// a not-yet-enabled backend shows an actionable message instead of crashing.
final ownerUidProvider = FutureProvider<String>((ref) async {
  return ref.watch(harnessAuthProvider).ensureSignedIn();
});

/// Live stream of the owner's reports (shared by the queue screen + the command
/// center's live counts).
final ownerReportsProvider =
    StreamProvider.family<List<Report>, String>((ref, uid) {
  return ref.watch(reportRepositoryProvider).watchReports(uid);
});
