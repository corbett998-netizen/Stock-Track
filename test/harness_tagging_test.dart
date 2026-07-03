import 'package:flutter_test/flutter_test.dart';
import 'package:stock_track/features/dev/chat/models/chat_item.dart';
import 'package:stock_track/features/dev/chat/models/workflow_tag.dart';
import 'package:stock_track/features/dev/chat/services/chat_repository.dart';
import 'package:stock_track/features/dev/chat/services/chat_tag_store.dart';
import 'package:stock_track/features/dev/chat/tagging/workflow_lane_registry.dart';
import 'package:stock_track/features/dev/services/harness_local_store.dart';
import 'package:stock_track/harness/harness_config.g.dart';

/// HI-11 chat message-tagging coverage. Pure + mock-path proof (no device):
///  - the tagging core (parse / dedup / normalise / fingerprint / common-checked),
///  - the LABEL dimension (b) end-to-end on the mock path (add → stored on the message →
///    survives a simulated restart → resolves back to the exact label on reload),
///  - the WORKFLOW dimension (a) is INERT at lanes.count==1 and would light up at >1,
///  - the portability landmine: addedAt is a CONCRETE client millis on the message, never
///    a server-timestamp sentinel.
/// Per doctrine the on-device add-a-label flow is the product-facing proof; these guard
/// the pure logic + write-through the surfaces rely on.
void main() {
  group('WorkflowTag.listFrom — defensive parse / dedup / normalise', () {
    test('parses fields, defaults kind to workflow, reads chatgpt label', () {
      final tags = WorkflowTag.listFrom(<Object?>[
        <String, dynamic>{'id': 'lane-a'}, // kind absent → workflow
        <String, dynamic>{
          'id': 'blue',
          'kind': 'chatgpt',
          'label': 'Blue Strategy',
          'addedBy': 'brandon',
          'addedAt': 1710000000000,
        },
      ]);
      expect(tags.length, 2);
      expect(tags[0].id, 'lane-a');
      expect(tags[0].kind, 'workflow');
      expect(tags[1].kind, 'chatgpt');
      expect(tags[1].label, 'Blue Strategy');
      expect(tags[1].addedBy, 'brandon');
      expect(tags[1].addedAtMs, 1710000000000);
    });

    test('any non-workflow kind normalises to chatgpt (zero migration)', () {
      final tags = WorkflowTag.listFrom(<Object?>[
        <String, dynamic>{'id': 'x', 'kind': 'advisor', 'label': 'L'},
      ]);
      expect(tags.single.kind, 'chatgpt');
    });

    test('dedup is on the (kind,id) pair — workflow x and chatgpt x coexist', () {
      final tags = WorkflowTag.listFrom(<Object?>[
        <String, dynamic>{'id': 'x', 'kind': 'workflow'},
        <String, dynamic>{'id': 'x', 'kind': 'workflow'}, // dup → dropped
        <String, dynamic>{'id': 'x', 'kind': 'chatgpt', 'label': 'X'},
      ]);
      expect(tags.length, 2);
      expect(tags.where((t) => t.kind == 'workflow').length, 1);
      expect(tags.where((t) => t.kind == 'chatgpt').length, 1);
    });

    test('malformed entries are skipped, never throw; null → empty', () {
      final tags = WorkflowTag.listFrom(<Object?>[
        'not-a-map',
        <String, dynamic>{'no': 'id'},
        <String, dynamic>{'id': ''},
        <String, dynamic>{'id': 'ok'},
      ]);
      expect(tags.single.id, 'ok');
      expect(WorkflowTag.listFrom(null), isEmpty);
    });
  });

  group('pure helpers — fingerprint + common-checked', () {
    test('fingerprint is order-independent; empty for untagged', () {
      const a = WorkflowTag(id: 'a', kind: 'chatgpt');
      const b = WorkflowTag(id: 'b', kind: 'workflow');
      expect(
        workflowTagFingerprint(<WorkflowTag>[a, b]),
        workflowTagFingerprint(<WorkflowTag>[b, a]),
      );
      expect(workflowTagFingerprint(const <WorkflowTag>[]), '');
    });

    test('commonTagIds = intersection (single AND many selection)', () {
      expect(commonTagIds(<Set<String>>[
        {'x', 'y'},
      ]), {'x', 'y'});
      expect(commonTagIds(<Set<String>>[
        {'x', 'y'},
        {'y', 'z'},
      ]), {'y'});
      expect(commonTagIds(const <Set<String>>[]), isEmpty);
    });
  });

  group('workflow dimension GATE — inert at one lane', () {
    test('workflowDimensionActive: false at 1 lane, true at >1', () {
      expect(workflowDimensionActive(1), isFalse);
      expect(workflowDimensionActive(2), isTrue);
    });

    test('generated gate mirrors the lane count from config', () {
      // The generated bool is the single source of truth the app reads; it must equal
      // the pure gate applied to the configured lane count.
      expect(
        HarnessConfig.taggingWorkflowEnabled,
        workflowDimensionActive(HarnessConfig.lanesCount),
      );
    });

    test('this single-lane port ships the workflow dimension INERT', () {
      expect(HarnessConfig.lanesCount, 1);
      expect(HarnessConfig.taggingWorkflowEnabled, isFalse);
      expect(WorkflowLaneRegistry.enabled, isFalse);
      // Dimension (b) — the free-form conversation label — is ON.
      expect(HarnessConfig.taggingLabelsEnabled, isTrue);
    });

    test('the lane SET is config-driven (the app OWN lane), never hardcoded', () {
      final lanes = WorkflowLaneRegistry.lanes();
      expect(lanes.length, HarnessConfig.lanesCount);
      // Derived from project.config.json:lanes.names — proves config drives it.
      expect(lanes.single.label, 'stocktrack-harness');
      expect(lanes.single.id, 'stocktrack-harness');
    });
  });

  group('ChatItem tag round-trip + portability landmine', () {
    test('tags survive toMap/fromMap; addedAt is a plain client int (no sentinel)', () {
      const item = ChatItem(
        id: 'm1',
        role: 'brandon',
        text: 'hello',
        createdAtMs: 5,
        tags: <WorkflowTag>[
          WorkflowTag(
            id: 'blue',
            kind: 'chatgpt',
            label: 'Blue',
            addedBy: 'brandon',
            addedAtMs: 1710000000000,
          ),
        ],
      );
      final map = item.toMap();
      final tagMap = (map['tags'] as List).single as Map<String, dynamic>;
      // The stored addedAt is a concrete int (client millis) — NOT a server-timestamp
      // sentinel. A serverTimestamp() inside an array element is illegal in Firestore.
      expect(tagMap['addedAt'], isA<int>());
      expect(tagMap['addedAt'], 1710000000000);

      final back = ChatItem.fromMap(map);
      expect(back.tags.single.label, 'Blue');
      expect(back.tags.single.kind, 'chatgpt');
      expect(back.tagFingerprint, isNotEmpty);
    });

    test('untagged item omits tags and round-trips identically', () {
      const item = ChatItem(id: 'm2', role: 'orchestrator', text: 'hi', createdAtMs: 1);
      expect(item.toMap().containsKey('tags'), isFalse);
      expect(ChatItem.fromMap(item.toMap()).tags, isEmpty);
    });
  });

  group('LABEL dimension end-to-end on the mock path (add → persist → reload)', () {
    test('writeTags stores the label on the message + survives a restart', () async {
      final store = InMemoryHarnessLocalStore();
      final repo = MockChatRepository(store);
      await repo.sendMessage(uid: 'u', text: 'tag me');
      final msg = (await repo.fetchMessages('u')).last;

      // Owner applies a free-form conversation label to the message.
      await repo.writeTags(
        uid: 'u',
        msgId: msg.id,
        tags: <WorkflowTag>[
          WorkflowTag(
            id: 'blue',
            kind: 'chatgpt',
            label: 'Blue',
            addedBy: 'brandon',
            addedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
      );
      final tagged = (await repo.fetchMessages('u')).firstWhere((m) => m.id == msg.id);
      expect(tagged.tags.single.label, 'Blue');

      // Simulate an app restart: a FRESH repo over the SAME store → the chip persists.
      final repo2 = MockChatRepository(store);
      final reloaded = (await repo2.fetchMessages('u')).firstWhere((m) => m.id == msg.id);
      expect(reloaded.tags.single.kind, 'chatgpt');
      expect(reloaded.tags.single.label, 'Blue');
    });

    test('writeTags is a no-op for an unknown (overlay-only) id — no junk doc', () async {
      final store = InMemoryHarnessLocalStore();
      final repo = MockChatRepository(store);
      final before = (await repo.fetchMessages('u')).length;
      await repo.writeTags(uid: 'u', msgId: 'ghost-id', tags: const <WorkflowTag>[]);
      expect((await repo.fetchMessages('u')).length, before);
    });

    test('store resolves the carried label with zero registry (fresh device)', () {
      // A fresh device has no persisted labels; the chip still shows the exact label
      // because it rides on the message element.
      final resolved = ChatTagStore().resolveTags(const <WorkflowTag>[
        WorkflowTag(id: 'blue', kind: 'chatgpt', label: 'Blue Strategy'),
      ]);
      expect(resolved.chatgpt.single.label, 'Blue Strategy');
      expect(resolved.workflow, isEmpty);
    });
  });
}
