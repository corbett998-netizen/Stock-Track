import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:stock_track/core/utils/harness_logger.dart';
import 'package:stock_track/features/dev/chat/models/chat_item.dart';
import 'package:stock_track/features/dev/chat/services/chat_export.dart';
import 'package:stock_track/features/dev/chat/services/chat_upload_service.dart';
import 'package:stock_track/features/dev/dev_gate.dart';
import 'package:stock_track/features/dev/report_queue/models/report.dart';
import 'package:stock_track/features/dev/report_queue/models/report_filter.dart';
import 'package:stock_track/features/dev/report_queue/services/report_repository.dart';
import 'package:stock_track/harness/harness_config.g.dart';

/// Unit coverage for the ported owner/operator harness logic (pure Dart — no
/// Firebase). The real owner-facing loop is proven on-device (see the port report),
/// per doctrine that a unit test is not product-facing proof; these guard the
/// pure model/config behaviour the ported surfaces rely on.
void main() {
  group('HarnessConfig (generated from Stock-Track project.config.json)', () {
    test('is pinned to Stock-Track, not Blueprint', () {
      expect(HarnessConfig.projectName, 'Stock-Track');
      expect(HarnessConfig.ownerRole, 'brandon');
      expect(HarnessConfig.reportsCollection, 'stockIssueReports');
    });

    test('carries no Blueprint identity literal', () {
      final all = [
        HarnessConfig.projectName,
        HarnessConfig.appName,
        HarnessConfig.ownerRole,
        HarnessConfig.chatRoot,
        HarnessConfig.reportsCollection,
        HarnessConfig.pushTitle,
        HarnessConfig.pushAndroidChannelId,
      ].join(' ').toLowerCase();
      for (final bad in const [
        'blueprint',
        'io.bcd',
        '9kc4uutkrjo9vj7pjut9yx528kj1',
        'mobileissuereports',
        'pete',
      ]) {
        expect(
          all.contains(bad),
          isFalse,
          reason: 'BP literal "$bad" leaked into HarnessConfig',
        );
      }
    });
  });

  group('HarnessLogger (generic device logger)', () {
    setUp(() => harnessLog.clear());

    test('records lines and snapshot returns them oldest→newest', () {
      harnessLog.chat('one');
      harnessLog.report('two');
      final snap = harnessLog.snapshot();
      expect(snap.contains('[chat] one'), isTrue);
      expect(snap.contains('[report] two'), isTrue);
      expect(snap.indexOf('one'), lessThan(snap.indexOf('two')));
    });

    test('snapshot(percent) returns only the most-recent slice', () {
      for (var i = 0; i < 10; i++) {
        harnessLog.system('line$i');
      }
      final half = harnessLog.snapshot(50);
      expect(half.contains('line9'), isTrue); // newest kept
      expect(half.contains('line0'), isFalse); // oldest dropped
    });

    test('inlineTail is byte-capped on a newline boundary', () {
      for (var i = 0; i < 50; i++) {
        harnessLog.system('x' * 100);
      }
      final tail = harnessLog.inlineTail(maxBytes: 500);
      expect(tail.length, lessThanOrEqualTo(500));
      // A partial leading line is dropped → no dangling fragment at the very start.
      expect(
        tail.startsWith('20'),
        isTrue,
      ); // an ISO timestamp begins each line
    });

    test('empty buffer snapshots to empty string', () {
      expect(harnessLog.snapshot(), isEmpty);
      expect(harnessLog.inlineTail(), isEmpty);
    });
  });

  group('Report.fromMap', () {
    test('reads logsInline / deviceInfo.platform / appBuild (Chunk 2)', () {
      final r = Report.fromMap('r-logs', {
        'note': 'x',
        'status': 'new',
        'logsInline': '2026 [chat] send OK',
        'deviceInfo': {'platform': 'android'},
        'appBuild': '1.0.0 (1)',
      }, createdAtMs: 0);
      expect(r.logsInline, '2026 [chat] send OK');
      expect(r.platform, 'android');
      expect(r.appBuild, '1.0.0 (1)');
    });

    test('parses fields + tolerates missing additive fields', () {
      final r = Report.fromMap('r1', {
        'note': 'Badge overlaps qty',
        'area': 'inventory',
        'status': 'new',
        'flaggedForOrchestrator': true,
      }, createdAtMs: 1000);
      expect(r.id, 'r1');
      expect(r.displayTitle, 'Badge overlaps qty');
      expect(r.area, 'inventory');
      expect(r.status, 'new');
      expect(r.flaggedForOrchestrator, isTrue);
      expect(r.manualResolved, isFalse);
      expect(r.recommendedFix, isNull);
    });

    test('effectiveStatus reads manual-resolved as fixed', () {
      final r = Report.fromMap('r2', {
        'note': 'x',
        'status': 'new',
        'manualResolved': true,
      }, createdAtMs: 0);
      expect(r.effectiveStatus, 'fixed');
    });

    test('resolves screenshot urls from map or string entries', () {
      final r = Report.fromMap('r3', {
        'note': 'x',
        'screenshots': [
          {'url': 'https://a/1.png', 'path': 'p'},
          'https://a/2.png',
          {'nope': true},
        ],
      }, createdAtMs: 0);
      expect(r.screenshots, ['https://a/1.png', 'https://a/2.png']);
    });
  });

  group('ReportFilter.matches', () {
    Report make(String status, {bool flagged = false, bool manual = false}) =>
        Report.fromMap('x', {
          'note': 'n',
          'status': status,
          'flaggedForOrchestrator': flagged,
          'manualResolved': manual,
        }, createdAtMs: 0);

    test('pending matches new/queued', () {
      expect(ReportFilter.pending.matches(make('new')), isTrue);
      expect(ReportFilter.pending.matches(make('fixed')), isFalse);
    });
    test('resolved matches fixed/wont_fix/manual', () {
      expect(ReportFilter.resolved.matches(make('fixed')), isTrue);
      expect(ReportFilter.resolved.matches(make('new', manual: true)), isTrue);
      expect(ReportFilter.resolved.matches(make('new')), isFalse);
    });
    test('flagged matches flaggedForOrchestrator', () {
      expect(ReportFilter.flagged.matches(make('new', flagged: true)), isTrue);
      expect(ReportFilter.flagged.matches(make('new')), isFalse);
    });
    test('all matches everything', () {
      expect(ReportFilter.all.matches(make('anything')), isTrue);
    });

    test('readyToTest matches awaitingVerification (Chunk 3)', () {
      final check = Report.fromMap('c', {
        'note': 'n',
        'status': 'fixed',
        'awaitingVerification': true,
      }, createdAtMs: 0);
      expect(ReportFilter.readyToTest.matches(check), isTrue);
      expect(ReportFilter.readyToTest.matches(make('new')), isFalse);
      // A still-awaiting check-item is NOT counted as resolved yet.
      expect(ReportFilter.resolved.matches(check), isFalse);
    });
  });

  group('Report dogfood fields (Chunk 3)', () {
    test('fromMap reads awaitingVerification / region / verifiedByUser', () {
      final r = Report.fromMap('c', {
        'note': 'Fixed X — verify on Inventory',
        'status': 'fixed',
        'area': 'build',
        'region': 'Inventory',
        'awaitingVerification': true,
        'verifiedByUser': false,
      }, createdAtMs: 0);
      expect(r.awaitingVerification, isTrue);
      expect(r.region, 'Inventory');
      expect(r.verifiedByUser, isFalse);
      expect(r.testOnLabel, 'Inventory');
    });

    test('testOnLabel falls back to area when region absent', () {
      final r = Report.fromMap('c', {
        'note': 'n',
        'area': 'build',
      }, createdAtMs: 0);
      expect(r.testOnLabel, 'build');
    });
  });

  group('ChatExport (Chunk 4 — paste-ready frames)', () {
    const owner = 'brandon';
    final items = [
      const ChatItem(
        id: 'a',
        role: 'orchestrator',
        text: 'hi',
        createdAtMs: 1000,
      ),
      const ChatItem(id: 'b', role: owner, text: 'go', createdAtMs: 2000),
    ];

    test('oneBubble labels owner vs orchestrator', () {
      expect(
        ChatExport.oneBubble(items[0], ownerRole: owner),
        contains('Orchestrator: hi'),
      );
      expect(
        ChatExport.oneBubble(items[1], ownerRole: owner),
        contains('Owner: go'),
      );
    });

    test('threadBlock joins all lines, no preamble', () {
      final block = ChatExport.threadBlock(items, ownerRole: owner);
      expect(block, contains('Orchestrator: hi'));
      expect(block, contains('Owner: go'));
      expect(block.contains('==='), isFalse);
    });

    test('fullFrame carries preamble + build + context header + thread', () {
      final frame = ChatExport.fullFrame(
        items: items,
        projectName: 'Stock-Track',
        ownerRole: owner,
        build: '1.0.0 (1)',
        context: {'lane': 'harness', 'state': 'green'},
      );
      expect(frame, contains('Stock-Track owner↔orchestrator context'));
      expect(frame, contains('App build: 1.0.0 (1)'));
      expect(frame, contains('Workflow state'));
      expect(frame, contains('Lane: harness'));
      expect(frame, contains('Owner: go'));
    });

    test('contextHeader degrades to empty when nothing published', () {
      expect(ChatExport.contextHeader(null), isEmpty);
      expect(ChatExport.contextHeader(const {}), isEmpty);
      // fullFrame still valid with no context.
      final frame = ChatExport.fullFrame(
        items: items,
        projectName: 'Stock-Track',
        ownerRole: owner,
      );
      expect(frame, contains('Conversation'));
      expect(frame.contains('Workflow state'), isFalse);
    });

    test('recentFrame only includes messages after the cursor', () {
      final recent = ChatExport.recentFrame(
        items: items,
        afterMs:
            1000, // excludes the first (==1000), includes the second (2000)
        projectName: 'Stock-Track',
        ownerRole: owner,
      );
      expect(recent, contains('Owner: go'));
      expect(recent.contains('Orchestrator: hi'), isFalse);
    });

    test('recentFrame is empty-honest when nothing is new', () {
      final recent = ChatExport.recentFrame(
        items: items,
        afterMs: 9999,
        projectName: 'Stock-Track',
        ownerRole: owner,
      );
      expect(recent, contains('no new messages'));
    });
  });

  group('Attachments — Storage-gated (Chunk 5)', () {
    test(
      'ChatUploadService returns the LOCAL path when Storage is off',
      () async {
        // Storage is deliberately off for the first proof.
        expect(kHarnessStorageEnabled, isFalse);
        final source = await ChatUploadService.resolve(
          XFile('/tmp/shot.png'),
          uid: 'u',
        );
        expect(source, '/tmp/shot.png'); // no upload attempted
      },
    );

    test('ChatUploadService returns null for no attachment', () async {
      expect(await ChatUploadService.resolve(null, uid: 'u'), isNull);
    });

    test('Report resolves a localPath screenshot entry (Storage off)', () {
      final r = Report.fromMap('r', {
        'note': 'x',
        'screenshots': [
          {'localPath': '/data/user/0/app/cache/pic.jpg', 'bytes': 10},
        ],
      }, createdAtMs: 0);
      expect(r.screenshots, ['/data/user/0/app/cache/pic.jpg']);
    });

    test('ChatItem carries an image attachment', () {
      const m = ChatItem(
        id: 'i',
        role: 'brandon',
        text: '',
        createdAtMs: 0,
        imageUrl: '/x/y.png',
      );
      expect(m.hasImage, isTrue);
      const t = ChatItem(id: 'i', role: 'brandon', text: 'hi', createdAtMs: 0);
      expect(t.hasImage, isFalse);
    });
  });

  group('MockReportRepository dogfood verify loop (Chunk 3)', () {
    const checkId = 'seed-checkitem-1';

    Future<List<Report>> snapshot(MockReportRepository repo) =>
        repo.watchReports('u').first;

    test('seeds a ready-to-test check-item', () async {
      final repo = MockReportRepository();
      final ready = (await snapshot(
        repo,
      )).where((r) => r.awaitingVerification).toList();
      expect(ready.length, 1);
      expect(ready.single.id, checkId);
    });

    test(
      'Works → resolved (clears awaitingVerification, stamps verified)',
      () async {
        final repo = MockReportRepository();
        await repo.markVerifiedWorks(checkId);
        final r = (await snapshot(repo)).firstWhere((x) => x.id == checkId);
        expect(r.awaitingVerification, isFalse);
        expect(r.verifiedByUser, isTrue);
        expect(r.manualResolved, isTrue);
        expect(r.effectiveStatus, 'fixed');
        expect(ReportFilter.readyToTest.matches(r), isFalse); // left the list
        expect(ReportFilter.resolved.matches(r), isTrue);
      },
    );

    test(
      'Still broken → reopen (status new, flagged, stays awaiting)',
      () async {
        final repo = MockReportRepository();
        await repo.markStillBroken(checkId);
        final r = (await snapshot(repo)).firstWhere((x) => x.id == checkId);
        expect(r.status, 'new');
        expect(r.flaggedForOrchestrator, isTrue);
        expect(r.manualResolved, isFalse);
        expect(r.awaitingVerification, isTrue); // still a live check-item
      },
    );

    test(
      'reopen bug fix: Resolved-then-dropdown-reopen actually reopens',
      () async {
        final repo = MockReportRepository();
        const bugId = 'seed-report-1';
        await repo.setManualResolved(bugId, value: true);
        var r = (await snapshot(repo)).firstWhere((x) => x.id == bugId);
        expect(r.effectiveStatus, 'fixed');
        // Pick a non-resolved status from the dropdown → must clear the stale tick.
        await repo.updateStatus(bugId, status: 'new');
        r = (await snapshot(repo)).firstWhere((x) => x.id == bugId);
        expect(r.manualResolved, isFalse);
        expect(r.effectiveStatus, 'new');
      },
    );
  });
}
