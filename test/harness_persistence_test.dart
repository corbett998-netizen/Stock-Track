import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_track/features/dev/chat/models/chat_item.dart';
import 'package:stock_track/features/dev/chat/services/chat_repository.dart';
import 'package:stock_track/features/dev/report_queue/models/report.dart';
import 'package:stock_track/features/dev/report_queue/services/report_repository.dart';
import 'package:stock_track/features/dev/services/harness_local_store.dart';

/// DATA-group correction coverage: durable local persistence behind the repo seam,
/// model round-trips, and restart-survival of the mock chat / report / dogfood loop.
/// Restart is simulated by building a FRESH mock repository over the SAME store
/// instance (the InMemory impl) and by a genuine re-read of the SharedPreferences
/// durable impl. Per doctrine, on-device restart is the product-facing proof; these
/// guard the pure serialization + write-through behaviour the surfaces rely on.
void main() {
  group('ChatItem toMap/fromMap round-trip', () {
    test('preserves every field incl createdAtMs + imageUrl', () {
      const item = ChatItem(
        id: 'x',
        role: 'brandon',
        text: 'hi there',
        createdAtMs: 1710000000000,
        imageUrl: '/a/b.png',
      );
      final back = ChatItem.fromMap(item.toMap());
      expect(back.id, item.id);
      expect(back.role, item.role);
      expect(back.text, item.text);
      expect(back.createdAtMs, item.createdAtMs);
      expect(back.imageUrl, item.imageUrl);
      expect(back.hasImage, isTrue);
    });

    test('text-only item omits imageUrl and round-trips', () {
      const item = ChatItem(
        id: 'y',
        role: 'orchestrator',
        text: 'ok',
        createdAtMs: 5,
      );
      expect(item.toMap().containsKey('imageUrl'), isFalse);
      final back = ChatItem.fromMap(item.toMap());
      expect(back.hasImage, isFalse);
      expect(back.createdAtMs, 5);
    });
  });

  group('Report toMap/fromMap round-trip (restart-survival serialization)', () {
    test('preserves dogfood + triage + evidence fields incl createdAtMs', () {
      final r = Report.fromMap(
        'r1',
        {
          'note': 'Badge overlaps',
          'area': 'inventory',
          'status': 'fixed',
          'screenshots': ['/data/pic1.png', '/data/pic2.png'],
          'comments': [
            {'text': 'still broken here', 'by': 'brandon', 'at': '2026-07-01'},
          ],
          'flaggedForOrchestrator': true,
          'manualResolved': true,
          'recommendedFix': 'reflow',
          'triageDecision': 'execute',
          'logsInline': '2026 [report] file OK',
          'deviceInfo': {'platform': 'android'},
          'appBuild': '1.0.0 (1)',
          'awaitingVerification': true,
          'region': 'Inventory',
          'verifiedByUser': true,
        },
        createdAtMs: 1710000000000,
      );

      // toMap must carry createdAtMs (fromMap does NOT read it from the map).
      final map = r.toMap();
      expect(map['createdAtMs'], 1710000000000);

      final back = Report.fromMap(
        map['id'] as String,
        map,
        createdAtMs: (map['createdAtMs'] as num).toInt(),
      );
      expect(back.id, 'r1');
      expect(back.createdAtMs, 1710000000000);
      expect(back.area, 'inventory');
      expect(back.status, 'fixed');
      expect(back.note, 'Badge overlaps');
      expect(back.screenshots, ['/data/pic1.png', '/data/pic2.png']);
      expect(back.comments.single['text'], 'still broken here');
      expect(back.flaggedForOrchestrator, isTrue);
      expect(back.manualResolved, isTrue);
      expect(back.recommendedFix, 'reflow');
      expect(back.triageDecision, 'execute');
      expect(back.logsInline, '2026 [report] file OK');
      expect(back.platform, 'android');
      expect(back.appBuild, '1.0.0 (1)');
      expect(back.awaitingVerification, isTrue);
      expect(back.region, 'Inventory');
      expect(back.verifiedByUser, isTrue);
      expect(back.testOnLabel, 'Inventory');
    });
  });

  group('InMemoryHarnessLocalStore', () {
    test('put / loadAll / delete / clear', () async {
      final store = InMemoryHarnessLocalStore();
      expect(store.loadAll('c'), isEmpty);
      await store.put('c', 'a', {'v': 1});
      await store.put('c', 'b', {'v': 2});
      expect(store.loadAll('c').keys, containsAll(<String>['a', 'b']));
      await store.delete('c', 'a');
      expect(store.loadAll('c').keys, ['b']);
      await store.clear('c');
      expect(store.loadAll('c'), isEmpty);
    });

    test('loadAll returns a copy — mutating it cannot corrupt the store', () async {
      final store = InMemoryHarnessLocalStore();
      await store.put('c', 'a', {'v': 1});
      store.loadAll('c')['a']!['v'] = 999;
      expect(store.loadAll('c')['a']!['v'], 1);
    });
  });

  group('MockChatRepository restart-survival (write-through store)', () {
    test('sent message survives a restart; seeds not duplicated', () async {
      final store = InMemoryHarnessLocalStore();
      final repo1 = MockChatRepository(store);
      await repo1.sendMessage(uid: 'u', text: 'hello after restart');

      // Restart: a brand-new repo hydrated from the SAME store.
      final repo2 = MockChatRepository(store);
      final items = await repo2.fetchMessages('u');
      expect(items.any((m) => m.text == 'hello after restart'), isTrue);
      expect(items.where((m) => m.id == 'seed-1').length, 1);
    });

    test('seeds only on empty store, ordered oldest→newest', () async {
      final items = await MockChatRepository(
        InMemoryHarnessLocalStore(),
      ).fetchMessages('u');
      expect(items.first.id, 'seed-1');
      expect(items.length, 2);
    });
  });

  group('MockReportRepository restart-survival (dogfood loop survives)', () {
    Future<List<Report>> snap(MockReportRepository r) =>
        r.watchReports('u').first;

    test(
      'filed report + Works verdict + comment survive restart; seeds not re-injected',
      () async {
        final store = InMemoryHarnessLocalStore();
        final repo1 = MockReportRepository(store);
        final id = await repo1.fileReport(uid: 'u', note: 'New bug from Inventory');
        await repo1.markVerifiedWorks('seed-checkitem-1');
        await repo1.addComment(id, text: 'context note');

        // Restart.
        final reports = await snap(MockReportRepository(store));

        final filed = reports.firstWhere((r) => r.id == id);
        expect(filed.note, 'New bug from Inventory');
        expect(filed.comments.any((c) => c['text'] == 'context note'), isTrue);

        // Dogfood verdict survived: the check-item is resolved, not awaiting.
        final check = reports.firstWhere((r) => r.id == 'seed-checkitem-1');
        expect(check.awaitingVerification, isFalse);
        expect(check.verifiedByUser, isTrue);
        expect(check.manualResolved, isTrue);

        // Seeds are not duplicated on reload.
        expect(reports.where((r) => r.id == 'seed-report-1').length, 1);
        expect(reports.where((r) => r.id == 'seed-checkitem-1').length, 1);
      },
    );

    test('Still-broken reopen survives restart (stays on ready-to-test)', () async {
      final store = InMemoryHarnessLocalStore();
      await MockReportRepository(store).markStillBroken('seed-checkitem-1');
      final reports = await snap(MockReportRepository(store));
      final check = reports.firstWhere((r) => r.id == 'seed-checkitem-1');
      expect(check.status, 'new');
      expect(check.flaggedForOrchestrator, isTrue);
      expect(check.awaitingVerification, isTrue);
    });
  });

  group('SharedPrefsHarnessLocalStore (durable impl — genuine re-read)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('a value written by one instance is read back by a fresh instance', () async {
      final s1 = await SharedPrefsHarnessLocalStore.create(
        namespace: 'ns',
        collections: const ['reports'],
      );
      await s1.put('reports', 'a', {'id': 'a', 'createdAtMs': 1, 'note': 'x'});

      // A brand-new instance re-reads from prefs = a real durable-store "restart".
      final s2 = await SharedPrefsHarnessLocalStore.create(
        namespace: 'ns',
        collections: const ['reports'],
      );
      expect(s2.loadAll('reports')['a']!['note'], 'x');
    });

    test('namespaces are isolated', () async {
      final a = await SharedPrefsHarnessLocalStore.create(
        namespace: 'appA',
        collections: const ['reports'],
      );
      await a.put('reports', 'x', {'v': 1});
      final b = await SharedPrefsHarnessLocalStore.create(
        namespace: 'appB',
        collections: const ['reports'],
      );
      expect(b.loadAll('reports'), isEmpty);
    });
  });
}
