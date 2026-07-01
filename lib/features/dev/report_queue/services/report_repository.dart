import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../harness/harness_config.g.dart';
import '../../report_capture/services/screenshot_upload_service.dart';
import '../models/report.dart';

/// THE Firestore seam for the report flow — every read/write against
/// `stockIssueReports` (+ the `system/orchestratorPoke` doc) lives here. Ported
/// from Blueprint's `ReportQueueRepository`; the collection name comes from the
/// generated [HarnessConfig] (`stockIssueReports`, deliberately distinct from BP's
/// `mobileIssueReports` so BP tooling can never point at it).
abstract interface class ReportRepository {
  /// Live stream of the signed-in owner's own reports, newest→oldest.
  Stream<List<Report>> watchReports(String uid);

  /// File a new report (optionally with screenshots) — the CAPTURE half.
  Future<void> fileReport({
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
                (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
          ),
      ]..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return reports;
    });
  }

  @override
  Future<void> fileReport({
    required String uid,
    required String note,
    List<XFile> screenshots = const <XFile>[],
  }) async {
    final shots = await ScreenshotUploadService.upload(screenshots, uid: uid);
    await _reports.add(<String, dynamic>{
      'userId': uid,
      'note': note,
      'noteOriginal': note,
      'title': note.split('\n').first.trim(),
      'area': 'general',
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      if (shots.isNotEmpty) 'screenshots': shots,
    });
    unawaited(pokeOrchestrator(note: 'new report filed').catchError((_) {}));
  }

  @override
  Future<void> pokeOrchestrator({String note = 'check queue'}) async {
    final trimmed = note.trim();
    await _db.doc(HarnessConfig.pokeDoc).set(<String, dynamic>{
      'pokedAt': FieldValue.serverTimestamp(),
      'note': trimmed.isEmpty ? 'check queue' : trimmed,
    });
  }

  Future<void> _update(String id, Map<String, dynamic> data) =>
      _reports.doc(id).update(data);

  @override
  Future<void> setTriageDecision(String reportId, {required String? decision}) =>
      _update(reportId, {
        'triageDecision': decision,
        'triageDecisionAt':
            decision == null ? null : FieldValue.serverTimestamp(),
        if (decision != null) 'flaggedForOrchestrator': true,
      });

  @override
  Future<void> updateStatus(String reportId, {required String status}) =>
      _update(reportId, {'status': status});

  @override
  Future<void> setManualResolved(String reportId, {required bool value}) =>
      _update(reportId, {
        'manualResolved': value,
        if (value) 'status': 'fixed',
      });

  @override
  Future<void> setFlagged(String reportId, bool value) =>
      _update(reportId, {'flaggedForOrchestrator': value});

  @override
  Future<void> addComment(String reportId, {required String text}) => _update(
        reportId,
        {
          'comments': FieldValue.arrayUnion([
            {
              'text': text,
              'at': DateTime.now().toIso8601String(),
              'by': HarnessConfig.ownerRole,
            },
          ]),
          'flaggedForOrchestrator': true,
        },
      );
}

/// In-memory reports for the Rung-0 demo (no Firebase). Seeded with one sample
/// report so the queue + triage controls are visibly usable before Brandon enables
/// the backend.
class MockReportRepository implements ReportRepository {
  MockReportRepository() {
    _reports.add(Report.fromMap(
      'seed-report-1',
      <String, dynamic>{
        'note': 'Low-stock badge overlaps the quantity on narrow phones.',
        'area': 'inventory',
        'status': 'new',
        'recommendedFix': 'Wrap the badge row so it reflows under the value.',
      },
      createdAtMs: DateTime.now().millisecondsSinceEpoch - 300000,
    ));
  }

  final List<Report> _reports = <Report>[];
  final StreamController<List<Report>> _controller =
      StreamController<List<Report>>.broadcast();

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
    _emit();
  }

  @override
  Stream<List<Report>> watchReports(String uid) async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Future<void> fileReport({
    required String uid,
    required String note,
    List<XFile> screenshots = const <XFile>[],
  }) async {
    _reports.add(Report.fromMap(
      'local-${DateTime.now().microsecondsSinceEpoch}',
      <String, dynamic>{
        'note': note,
        'area': 'general',
        'status': 'new',
        'screenshots': [for (final s in screenshots) s.path],
      },
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    _emit();
  }

  @override
  Future<void> pokeOrchestrator({String note = 'check queue'}) async {}

  @override
  Future<void> setTriageDecision(String reportId, {required String? decision}) async =>
      _replace(reportId, (r) => _copy(r, triageDecision: decision, flagged: decision != null ? true : r.flaggedForOrchestrator));

  @override
  Future<void> updateStatus(String reportId, {required String status}) async =>
      _replace(reportId, (r) => _copy(r, status: status));

  @override
  Future<void> setManualResolved(String reportId, {required bool value}) async =>
      _replace(reportId, (r) => _copy(r, manualResolved: value, status: value ? 'fixed' : r.status));

  @override
  Future<void> setFlagged(String reportId, bool value) async =>
      _replace(reportId, (r) => _copy(r, flagged: value));

  @override
  Future<void> addComment(String reportId, {required String text}) async =>
      _replace(reportId, (r) {
        final comments = List<Map<String, dynamic>>.of(r.comments)
          ..add({'text': text, 'at': DateTime.now().toIso8601String(), 'by': HarnessConfig.ownerRole});
        return _copy(r, comments: comments, flagged: true);
      });

  Report _copy(
    Report r, {
    String? status,
    bool? manualResolved,
    bool? flagged,
    Object? triageDecision = _unset,
    List<Map<String, dynamic>>? comments,
  }) =>
      Report(
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
        triageDecision:
            identical(triageDecision, _unset) ? r.triageDecision : triageDecision as String?,
      );

  static const Object _unset = Object();
}
