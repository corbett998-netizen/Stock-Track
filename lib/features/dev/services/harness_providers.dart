import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/harness_app_build.dart';
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
final ownerReportsProvider = StreamProvider.family<List<Report>, String>((
  ref,
  uid,
) {
  return ref.watch(reportRepositoryProvider).watchReports(uid);
});

/// The host app's build/version string (e.g. `1.0.0 (1)`) — shown on the command
/// center and stamped on reports. App-agnostic: reads whatever app the harness is
/// compiled into via `package_info_plus`.
final harnessAppBuildProvider = FutureProvider<String>((ref) async {
  return resolveHarnessAppBuild();
});

/// The published `system/workflowContext` projection (or null when nothing is
/// published). Read-only in-app; the operator side publishes it. Feeds the chat
/// dashboard sheet + the ChatGPT-export context header.
final workflowContextProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  return ref.watch(chatRepositoryProvider).readWorkflowContext();
});

/// The `system/agentStatus` doc (or null). Read-only in-app; feeds the "N agents
/// engaged" header signal.
final agentStatusProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  return ref.watch(chatRepositoryProvider).readAgentStatus();
});

/// The "N agents engaged" count derived from [agentStatusProvider] — reads an
/// `engaged` int or the length of an `agents` list; 0 when nothing is published.
int agentsEngagedCount(Map<String, dynamic>? status) {
  if (status == null) return 0;
  final engaged = status['engaged'];
  if (engaged is int) return engaged;
  if (engaged is num) return engaged.toInt();
  final agents = status['agents'];
  if (agents is List) return agents.length;
  return 0;
}
