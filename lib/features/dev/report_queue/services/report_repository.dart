import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/current_screen_tracker.dart';
import '../../../../core/utils/harness_app_build.dart';
import '../../../../core/utils/harness_logger.dart';
import '../../../../harness/harness_config.g.dart';
import '../../report_capture/services/screenshot_upload_service.dart';
import '../../services/harness_local_store.dart';
import '../models/report.dart';

/// THE Firestore seam for the report flow — every read/write against
/// `stockIssueReports` (+ the `system/orchestratorPoke` doc) lives here. Ported
/// from Blueprint's `ReportQueueRepository`; the collection name comes from the
/// generated [HarnessConfig] (`stockIssueReports`, deliberately distinct from BP's
/// `mobileIssueReports` so BP tooling can never point at it).
abstract interface class ReportRepository {
  /// Live stream of the signed-in owner's own reports, newest→oldest.
  Stream<List<Report>> watchReports(String uid);

  /// File a new report (optionally with screenshots) — the CAPTURE half. Returns
  /// the new report's id so the capture UI can show a copyable handle.
  Future<String> fileReport({
    required String uid,
    required String note,
    List<XFile> screenshots = const <XFile>[],
  });

  /// Bump `system/orchestratorPoke` so the orchestrator checks the queue now.
  Future<void> pokeOrchestrator({String note = 'check queue'});

  // ----- Owner triage actions -----
  Future<void> setTriageDecision(String reportId, {required String? decision});
  Future<void> updateStatus(String reportId, {required String status});
  Future<void> setManualResolved(String reportId, {required bool value});
  Future<void> setFlagged(String reportId, bool value);
  Future<void> addComment(String reportId, {required String text});

  // ----- Dogfood verify loop (Ready-to-test) -----
  /// Owner confirmed the check-item is fixed ("Works") — canonical resolved write.
  Future<void> markVerifiedWorks(String reportId);

  /// Owner says the check-item is still broken — canonical reopen write.
  Future<void> markStillBroken(String reportId);
}

/// Firestore-backed reports against Brandon's project (easy-stock-track).
class FirebaseReportRepository implements ReportRepository {
  FirebaseReportRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(HarnessConfig.reportsCollection);

  @override
  Stream<List<Report>> watchReports(String uid) {
    // Single `where` (no composite orderBy) → no composite index required for the
    // dogfood; sort newest-first client-side.
    return _reports.where('userId', isEqualTo: uid).snapshots().map((snap) {
      final reports = <Report>[
        for (final d in snap.docs)
          Report.fromMap(
            d.id,
            d.data(),
            createdAtMs:
                (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                0,
          ),
      ]..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return reports;
    });
  }

  @override
  Future<String> fileReport({
    required String uid,
    required String note,
    List<XFile> screenshots = const <XFile>[],
  }) async {
    harnessLog.report(
      'file: "${_firstLine(note)}" (${screenshots.length} shots)',
    );
    final shots = await ScreenshotUploadService.upload(screenshots, uid: uid);
    // Evidence captured at submit: device-log tail, capture platform, the app build
    // that produced it (logs-first, answerable "which build"), and the SCREEN the
    // owner was on ("which screen was I on" — the fastest triage signal).
    final logsInline = harnessLog.inlineTail();
    final appBuild = await resolveHarnessAppBuild();
    final screen = CurrentScreenTracker.currentScreen;
    final ref = await _reports.add(<String, dynamic>{
      'userId': uid,
      'note': note,
      'noteOriginal': note,
      'title': _firstLine(note),
      'area': 'general',
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'deviceInfo': <String, dynamic>{'platform': defaultTargetPlatform.name},
      'appBuild': appBuild,
      if (screen != null && screen.isNotEmpty) 'region': screen,
      if (logsInline.isNotEmpty) 'logsInline': logsInline,
      if (shots.isNotEmpty) 'screenshots': shots,
    });
    harnessLog.report(
      'filed OK ${ref.id} (${logsInline.length}B logs, build $appBuild)',
    );
    unawaited(pokeOrchestrator(note: 'new report filed').catchError((_) {}));
    return ref.id;
  }

  static String _firstLine(String s) => s.split('\n').first.trim();

  @override
  Future<void> pokeOrchestrator({String note = 'check queue'}) async {
    final trimmed = note.trim();
    harnessLog.system('poke: ${trimmed.isEmpty ? 'check queue' : trimmed}');
    await _db.doc(HarnessConfig.pokeDoc).set(<String, dynamic>{
      'pokedAt': FieldValue.serverTimestamp(),
      'note': trimmed.isEmpty ? 'check queue' : trimmed,
    });
  }

  // ===== Canonical resolved/reopened field-sets ============================
  // ONE definition each, shared by the queue triage controls AND the ready-to-test
  // sheet, so the two live surfaces over the same docs can never drift.

  /// The write that RESOLVES a report (manual tick or dogfood "Works"). Clears the
  /// verify flag and stamps a resolve time; [verifiedByUser] marks a dogfood pass.
  static Map<String, dynamic> resolvedFields({bool verifiedByUser = false}) =>
      <String, dynamic>{
        'manualResolved': true,
        'status': 'fixed',
        'awaitingVerification': false,
        'resolvedAt': FieldValue.serverTimestamp(),
        if (verifiedByUser) 'verifiedByUser': true,
      };

  /// The write that REOPENS a report (dropdown reopen or dogfood "Still broken").
  /// Clears the stale manual-resolved tick (THE reopen-bug fix) and flags the
  /// orchestrator; [keepAwaitingVerification] keeps a dogfood item on the list.
  static Map<String, dynamic> reopenedFields({
    bool keepAwaitingVerification = false,
  }) => <String, dynamic>{
    'status': 'new',
    'manualResolved': false,
    'flaggedForOrchestrator': true,
    'verifiedByUser': false,
    'awaitingVerification': keepAwaitingVerification,
  };

  Future<void> _update(String id, Map<String, dynamic> data) =>
      _reports.doc(id).update(data);

  @override
  Future<void> setTriageDecision(
    String reportId, {
    required String? decision,
  }) => _update(reportId, {
    'triageDecision': decision,
    'triageDecisionAt': decision == null ? null : FieldValue.serverTimestamp(),
    if (decision != null) 'flaggedForOrchestrator': true,
  });

  @override
  Future<void> updateStatus(String reportId, {required String status}) {
    final resolvedLike = status == 'fixed' || status == 'wont_fix';
    if (resolvedLike) {
      return _update(reportId, <String, dynamic>{'status': status});
    }
    // Reopen: build from the CANONICAL reopened field-set (clears the stale
    // manual-resolved tick etc.) so the dropdown reopen and the dogfood
    // "Still broken" write stay in lockstep; keep the owner's chosen status.
    return _update(reportId, <String, dynamic>{
      ...reopenedFields(),
      'status': status,
    });
  }

  @override
  Future<void> setManualResolved(String reportId, {required bool value}) =>
      _update(
        reportId,
        value ? resolvedFields() : <String, dynamic>{'manualResolved': false},
      );

  @override
  Future<void> markVerifiedWorks(String reportId) {
    harnessLog.report('dogfood Works → resolved: $reportId');
    return _update(reportId, resolvedFields(verifiedByUser: true));
  }

  @override
  Future<void> markStillBroken(String reportId) {
    harnessLog.report('dogfood Still-broken → reopen: $reportId');
    return _update(reportId, reopenedFields(keepAwaitingVerification: true));
  }

  @override
  Future<void> setFlagged(String reportId, bool value) =>
      _update(reportId, {'flaggedForOrchestrator': value});

  @override
  Future<void> addComment(String reportId, {required String text}) =>
      _update(reportId, {
        'comments': FieldValue.arrayUnion([
          {
            'text': text,
            'at': DateTime.now().toIso8601String(),
            'by': HarnessConfig.ownerRole,
          },
        ]),
        'flaggedForOrchestrator': true,
      });
}

/// In-memory reports for the Rung-0 demo (no Firebase), now DURABLE across app
/// restart via a [HarnessLocalStore] write-through. The mock path used to hold the
/// ENTIRE report/queue/dogfood loop in memory, so every restart re-seeded and lost
/// every filed report + Works/Still-broken verdict + triage/comment. Because the
/// ready-to-test surface is DERIVED from report fields (`awaitingVerification` etc.),
/// persisting the reports collection makes the whole dogfood loop survive restart —
/// no separate store needed. The store defaults to [InMemoryHarnessLocalStore] so
/// existing callers / tests that construct it with no args keep the old behaviour;
/// lib/main.dart passes the shared prefs-backed store in mock mode.
class MockReportRepository implements ReportRepository {
  MockReportRepository([HarnessLocalStore? store])
    : _store = store ?? InMemoryHarnessLocalStore() {
    final loaded = _store.loadAll(HarnessStoreKeys.reports);
    if (loaded.isEmpty) {
      // Fresh install (empty store) → seed AND persist. Re-seed is gated on
      // box-EMPTY (not "seed id absent") so a cleared seed is never re-injected.
      _seed();
    } else {
      for (final entry in loaded.entries) {
        final json = entry.value;
        _reports.add(
          Report.fromMap(
            entry.key,
            json,
            // fromMap does NOT read createdAtMs from the map — pass it back from the
            // stored value explicitly (the load-bearing round-trip detail).
            createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
  }

  final HarnessLocalStore _store;
  final List<Report> _reports = <Report>[];
  final StreamController<List<Report>> _controller =
      StreamController<List<Report>>.broadcast();

  void _seed() {
    final seeds = <Report>[
      Report.fromMap(
        'seed-report-1',
        <String, dynamic>{
          'note': 'Low-stock badge overlaps the quantity on narrow phones.',
          'area': 'inventory',
          'status': 'new',
          'recommendedFix': 'Wrap the badge row so it reflows under the value.',
        },
        createdAtMs: DateTime.now().millisecondsSinceEpoch - 300000,
      ),
      // A seeded dogfood check-item so the "Ready to test" surface is visibly usable
      // in mock mode (mirrors what `stocktrack_chat.js --build` writes).
      Report.fromMap(
        'seed-checkitem-1',
        <String, dynamic>{
          'note':
              'Fixed: low-stock badge reflow — verify on the Inventory list.',
          'area': 'build',
          'region': 'Inventory',
          'status': 'fixed',
          'awaitingVerification': true,
          'backfilled': true,
        },
        createdAtMs: DateTime.now().millisecondsSinceEpoch - 60000,
      ),
    ];
    _reports.addAll(seeds);
    for (final r in seeds) {
      _persist(r);
    }
  }

  /// Write one report through to the durable store (best-effort). The in-memory
  /// `_reports` list stays the live source; the store is its durable mirror.
  void _persist(Report r) =>
      unawaited(_store.put(HarnessStoreKeys.reports, r.id, r.toMap()));

  List<Report> get _snapshot {
    final copy = List<Report>.of(_reports)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return List.unmodifiable(copy);
  }

  void _emit() => _controller.add(_snapshot);

  int _indexOf(String id) => _reports.indexWhere((r) => r.id == id);

  void _replace(String id, Report Function(Report) f) {
    final i = _indexOf(id);
    if (i == -1) return;
    _reports[i] = f(_reports[i]);
    // Single write-through choke-point: every triage/dogfood transition funnels
    // through here (Works / Still-broken / reopen / flag / comment / status /
    // manualResolved / triageDecision), so persisting here makes all of them
    // survive restart.
    _persist(_reports[i]);
    _emit();
  }

  @override
  Stream<List<Report>> watchReports(String uid) async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Future<String> fileReport({
    required String uid,
    required String note,
    List<XFile> screenshots = const <XFile>[],
  }) async {
    harnessLog.report('file (mock): "${note.split('\n').first.trim()}"');
    final logsInline = harnessLog.inlineTail();
    final appBuild = await resolveHarnessAppBuild();
    final screen = CurrentScreenTracker.currentScreen;
    final id = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    final report = Report.fromMap(id, <String, dynamic>{
      'note': note,
      'area': 'general',
      'status': 'new',
      // Local file paths (Storage off / mock) — rendered on-device.
      'screenshots': [
        for (final s in screenshots) {'localPath': s.path},
      ],
      'deviceInfo': <String, dynamic>{'platform': defaultTargetPlatform.name},
      'appBuild': appBuild,
      // Screen-context ("which screen was I on") captured at submit — the report
      // keeps it (with the log-tail + build/platform) and it renders on reload.
      if (screen != null && screen.isNotEmpty) 'region': screen,
      if (logsInline.isNotEmpty) 'logsInline': logsInline,
    }, createdAtMs: createdAtMs);
    _reports.add(report);
    // Write through so a filed report + its evidence survives an app restart.
    _persist(report);
    _emit();
    return id;
  }

  @override
  Future<void> pokeOrchestrator({String note = 'check queue'}) async {
    harnessLog.system('poke (mock): ${note.trim()}');
  }

  @override
  Future<void> setTriageDecision(
    String reportId, {
    required String? decision,
  }) async => _replace(
    reportId,
    (r) => _copy(
      r,
      triageDecision: decision,
      flagged: decision != null ? true : r.flaggedForOrchestrator,
    ),
  );

  @override
  Future<void> updateStatus(String reportId, {required String status}) async {
    final resolvedLike = status == 'fixed' || status == 'wont_fix';
    // Mirror the canonical reopened field-set (see FirebaseReportRepository
    // .reopenedFields): a non-resolved status clears the stale tick + verify flags
    // and flags the orchestrator; keep the owner's chosen status.
    _replace(
      reportId,
      (r) => resolvedLike
          ? _copy(r, status: status)
          : _copy(
              r,
              status: status,
              manualResolved: false,
              flagged: true,
              verifiedByUser: false,
              awaitingVerification: false,
            ),
    );
  }

  @override
  Future<void> setManualResolved(
    String reportId, {
    required bool value,
  }) async => _replace(
    reportId,
    (r) => value
        ? _copy(
            r,
            manualResolved: true,
            status: 'fixed',
            awaitingVerification: false,
          )
        : _copy(r, manualResolved: false),
  );

  @override
  Future<void> markVerifiedWorks(String reportId) async {
    harnessLog.report('dogfood Works → resolved (mock): $reportId');
    _replace(
      reportId,
      (r) => _copy(
        r,
        manualResolved: true,
        status: 'fixed',
        awaitingVerification: false,
        verifiedByUser: true,
      ),
    );
  }

  @override
  Future<void> markStillBroken(String reportId) async {
    harnessLog.report('dogfood Still-broken → reopen (mock): $reportId');
    _replace(
      reportId,
      (r) => _copy(
        r,
        status: 'new',
        manualResolved: false,
        flagged: true,
        awaitingVerification: true,
        verifiedByUser: false,
      ),
    );
  }

  @override
  Future<void> setFlagged(String reportId, bool value) async =>
      _replace(reportId, (r) => _copy(r, flagged: value));

  @override
  Future<void> addComment(String reportId, {required String text}) async =>
      _replace(reportId, (r) {
        final comments = List<Map<String, dynamic>>.of(r.comments)
          ..add({
            'text': text,
            'at': DateTime.now().toIso8601String(),
            'by': HarnessConfig.ownerRole,
          });
        return _copy(r, comments: comments, flagged: true);
      });

  Report _copy(
    Report r, {
    String? status,
    bool? manualResolved,
    bool? flagged,
    Object? triageDecision = _unset,
    List<Map<String, dynamic>>? comments,
    bool? awaitingVerification,
    bool? verifiedByUser,
  }) => Report(
    id: r.id,
    createdAtMs: r.createdAtMs,
    area: r.area,
    status: status ?? r.status,
    note: r.note,
    screenshots: r.screenshots,
    comments: comments ?? r.comments,
    flaggedForOrchestrator: flagged ?? r.flaggedForOrchestrator,
    manualResolved: manualResolved ?? r.manualResolved,
    recommendedFix: r.recommendedFix,
    triageDecision: identical(triageDecision, _unset)
        ? r.triageDecision
        : triageDecision as String?,
    logsInline: r.logsInline,
    deviceInfo: r.deviceInfo,
    appBuild: r.appBuild,
    awaitingVerification: awaitingVerification ?? r.awaitingVerification,
    region: r.region,
    verifiedByUser: verifiedByUser ?? r.verifiedByUser,
  );

  static const Object _unset = Object();
}
