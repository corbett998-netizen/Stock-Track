import 'package:flutter_test/flutter_test.dart';
import 'package:stock_track/features/dev/report_queue/models/report.dart';
import 'package:stock_track/features/dev/report_queue/models/report_filter.dart';
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
        expect(all.contains(bad), isFalse, reason: 'BP literal "$bad" leaked into HarnessConfig');
      }
    });
  });

  group('Report.fromMap', () {
    test('parses fields + tolerates missing additive fields', () {
      final r = Report.fromMap(
        'r1',
        {
          'note': 'Badge overlaps qty',
          'area': 'inventory',
          'status': 'new',
          'flaggedForOrchestrator': true,
        },
        createdAtMs: 1000,
      );
      expect(r.id, 'r1');
      expect(r.displayTitle, 'Badge overlaps qty');
      expect(r.area, 'inventory');
      expect(r.status, 'new');
      expect(r.flaggedForOrchestrator, isTrue);
      expect(r.manualResolved, isFalse);
      expect(r.recommendedFix, isNull);
    });

    test('effectiveStatus reads manual-resolved as fixed', () {
      final r = Report.fromMap('r2', {'note': 'x', 'status': 'new', 'manualResolved': true}, createdAtMs: 0);
      expect(r.effectiveStatus, 'fixed');
    });

    test('resolves screenshot urls from map or string entries', () {
      final r = Report.fromMap(
        'r3',
        {
          'note': 'x',
          'screenshots': [
            {'url': 'https://a/1.png', 'path': 'p'},
            'https://a/2.png',
            {'nope': true},
          ],
        },
        createdAtMs: 0,
      );
      expect(r.screenshots, ['https://a/1.png', 'https://a/2.png']);
    });
  });

  group('ReportFilter.matches', () {
    Report make(String status, {bool flagged = false, bool manual = false}) =>
        Report.fromMap('x', {'note': 'n', 'status': status, 'flaggedForOrchestrator': flagged, 'manualResolved': manual}, createdAtMs: 0);

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
  });
}
