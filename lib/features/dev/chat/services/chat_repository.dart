import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../harness/harness_config.g.dart';
import '../../services/harness_local_store.dart';
import '../models/chat_item.dart';

/// THE data-access seam for the owner↔orchestrator chat — one place that owns the
/// query shape + the write/poke contract, so the surface can be retargeted (Mock →
/// easy-stock-track) without touching the controller/screen. Ported from
/// Blueprint's `ChatRepository`; the collection/doc names come from the generated
/// [HarnessConfig] (Stock-Track values), never a BP literal.
///
/// Data model (one thread per owner UID, in easy-stock-track):
/// ```
/// orchestratorChat/{uid}/messages/{auto} = {
///   role: 'brandon' | 'orchestrator',
///   text, createdAt: serverTimestamp(), via: 'text',
/// }
/// ```
/// Every owner send also bumps `system/orchestratorPoke` so the poll-based
/// orchestrator wakes — the message IS the poke.
abstract interface class ChatRepository {
  /// Live stream of the thread, oldest→newest. (Firebase: a `snapshots()` Watch
  /// listener; Mock: a broadcast of in-memory state.)
  Stream<List<ChatItem>> watchMessages(String uid);

  /// One-shot re-get, oldest→newest. Firebase reads from the SERVER (the
  /// deterministic poll lever that BP added because the device Watch stream is not
  /// reliably real-time); Mock returns the current snapshot.
  Future<List<ChatItem>> fetchMessages(String uid);

  /// Append an owner message and bump the orchestrator poke (best-effort).
  /// [imageSource] is an optional attached image (Storage URL or local path).
  Future<void> sendMessage({
    required String uid,
    required String text,
    String via = 'text',
    String? imageSource,
  });

  /// Read the published `system/workflowContext` projection (or null when nothing
  /// is published yet — the dashboard shows an empty-but-honest state). Read-only
  /// from the app; the operator side publishes it (Chunk 6).
  Future<Map<String, dynamic>?> readWorkflowContext();

  /// Read the `system/agentStatus` doc (or null). Feeds the "N agents engaged"
  /// header signal. Read-only in-app; the operator side writes it.
  Future<Map<String, dynamic>?> readAgentStatus();
}

/// Firestore-backed chat against Brandon's project (easy-stock-track).
class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> _query(String uid) => _db
      .collection(HarnessConfig.chatRoot)
      .doc(uid)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(200);

  CollectionReference<Map<String, dynamic>> _messages(String uid) =>
      _db.collection(HarnessConfig.chatRoot).doc(uid).collection('messages');

  List<ChatItem> _itemsFrom(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsDesc,
  ) {
    // The query is descending; reverse to oldest→newest for rendering.
    return <ChatItem>[
      for (final d in docsDesc.reversed)
        ChatItem(
          id: d.id,
          role: (d.data()['role'] ?? 'orchestrator').toString(),
          text: (d.data()['text'] ?? '').toString(),
          createdAtMs:
              (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
              0,
          imageUrl: d.data()['imageUrl'] as String?,
        ),
    ];
  }

  @override
  Stream<List<ChatItem>> watchMessages(String uid) =>
      _query(uid).snapshots().map((s) => _itemsFrom(s.docs));

  @override
  Future<List<ChatItem>> fetchMessages(String uid) async {
    final snap = await _query(uid).get(const GetOptions(source: Source.server));
    return _itemsFrom(snap.docs);
  }

  @override
  Future<void> sendMessage({
    required String uid,
    required String text,
    String via = 'text',
    String? imageSource,
  }) async {
    // 1) the message — the critical write the send awaits.
    final add = _messages(uid).add(<String, dynamic>{
      'role': HarnessConfig.ownerRole,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'via': via,
      'area': 'general',
      if (imageSource != null && imageSource.isNotEmpty)
        'imageUrl': imageSource,
    });
    // 2) bump the poke — fire-and-forget so it can never fail the send.
    final truncated = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    unawaited(
      _db
          .doc(HarnessConfig.pokeDoc)
          .set(<String, dynamic>{
            'pokedAt': FieldValue.serverTimestamp(),
            'note': 'chat: $truncated',
            'by': uid,
          })
          .catchError((_) {}),
    );
    await add;
  }

  @override
  Future<Map<String, dynamic>?> readWorkflowContext() async {
    try {
      final doc = await _db.doc(HarnessConfig.workflowContextDoc).get();
      return doc.exists ? doc.data() : null;
    } catch (_) {
      // Backend not ready / offline → treat as "nothing published".
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> readAgentStatus() async {
    try {
      final doc = await _db.doc(HarnessConfig.agentStatusDoc).get();
      return doc.exists ? doc.data() : null;
    } catch (_) {
      return null;
    }
  }
}

/// In-memory chat for the Rung-0 demo (no Firebase), now DURABLE across app restart
/// via a [HarnessLocalStore] write-through (the mock path used to reset to seeds on
/// every launch). The store defaults to [InMemoryHarnessLocalStore] so existing
/// callers / tests that construct it with no args keep the old in-memory behaviour;
/// lib/main.dart passes the shared prefs-backed store in mock mode.
///
/// To keep the demo honest, it still does NOT fabricate an orchestrator — the
/// owner's sends just persist locally (the real two-way channel needs the backend).
class MockChatRepository implements ChatRepository {
  MockChatRepository([HarnessLocalStore? store])
    : _store = store ?? InMemoryHarnessLocalStore() {
    final loaded = _store.loadAll(HarnessStoreKeys.chat);
    if (loaded.isEmpty) {
      // Fresh install (empty store) → seed AND persist, so seeds appear only once
      // and the owner's later messages accumulate on top of them across restarts.
      _seed();
    } else {
      _messages.addAll(
        loaded.values.map(ChatItem.fromMap).toList()
          ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs)),
      );
    }
  }

  final HarnessLocalStore _store;
  final List<ChatItem> _messages = <ChatItem>[];
  final StreamController<List<ChatItem>> _controller =
      StreamController<List<ChatItem>>.broadcast();

  void _seed() {
    final base = DateTime.now().millisecondsSinceEpoch - 120000;
    final seeds = <ChatItem>[
      ChatItem(
        id: 'seed-1',
        role: 'orchestrator',
        text:
            'Stock-Track harness online (mock mode). This is the ported '
            'Blueprint owner/orchestrator chat running inside Stock-Track.',
        createdAtMs: base,
      ),
      ChatItem(
        id: 'seed-2',
        role: HarnessConfig.ownerRole,
        text: 'Nice — same chat surface, different app.',
        createdAtMs: base + 30000,
      ),
    ];
    _messages.addAll(seeds);
    for (final s in seeds) {
      unawaited(_store.put(HarnessStoreKeys.chat, s.id, s.toMap()));
    }
  }

  List<ChatItem> get _snapshot => List.unmodifiable(_messages);

  @override
  Stream<List<ChatItem>> watchMessages(String uid) async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Future<List<ChatItem>> fetchMessages(String uid) async => _snapshot;

  @override
  Future<void> sendMessage({
    required String uid,
    required String text,
    String via = 'text',
    String? imageSource,
  }) async {
    final item = ChatItem(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: HarnessConfig.ownerRole,
      text: text,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      imageUrl: imageSource,
    );
    _messages.add(item);
    // Write through so the sent message survives an app restart (mock path).
    unawaited(_store.put(HarnessStoreKeys.chat, item.id, item.toMap()));
    _controller.add(_snapshot);
  }

  @override
  Future<Map<String, dynamic>?> readWorkflowContext() async {
    // A seeded demo projection so the dashboard is visibly usable in mock mode
    // (mirrors what the Chunk-6 publisher writes to system/workflowContext).
    return <String, dynamic>{
      'lane': 'harness-parity (demo)',
      'build': '${HarnessConfig.projectName} dev',
      'state': 'Mock mode — no live backend; this is a seeded demo projection.',
      'waitingOnOwner': 'nothing right now',
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>?> readAgentStatus() async => <String, dynamic>{
    'engaged': 1,
  };
}
