import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../harness/harness_config.g.dart';
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
  Future<void> sendMessage({
    required String uid,
    required String text,
    String via = 'text',
  });
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
              (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
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
  }) async {
    // 1) the message — the critical write the send awaits.
    final add = _messages(uid).add(<String, dynamic>{
      'role': HarnessConfig.ownerRole,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'via': via,
      'area': 'general',
    });
    // 2) bump the poke — fire-and-forget so it can never fail the send.
    final truncated = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    unawaited(
      _db.doc(HarnessConfig.pokeDoc).set(<String, dynamic>{
        'pokedAt': FieldValue.serverTimestamp(),
        'note': 'chat: $truncated',
        'by': uid,
      }).catchError((_) {}),
    );
    await add;
  }
}

/// In-memory chat for the Rung-0 demo (no Firebase). Seeded with a short thread so
/// the ported UI is visibly usable before Brandon enables the backend. To keep the
/// demo honest, it does NOT fabricate an orchestrator — the owner's sends just
/// persist to memory (the real two-way channel needs easy-stock-track + ADC).
class MockChatRepository implements ChatRepository {
  MockChatRepository() {
    final base = DateTime.now().millisecondsSinceEpoch - 120000;
    _messages.addAll([
      ChatItem(
        id: 'seed-1',
        role: 'orchestrator',
        text: 'Stock-Track harness online (mock mode). This is the ported '
            'Blueprint owner/orchestrator chat running inside Stock-Track.',
        createdAtMs: base,
      ),
      ChatItem(
        id: 'seed-2',
        role: HarnessConfig.ownerRole,
        text: 'Nice — same chat surface, different app.',
        createdAtMs: base + 30000,
      ),
    ]);
  }

  final List<ChatItem> _messages = <ChatItem>[];
  final StreamController<List<ChatItem>> _controller =
      StreamController<List<ChatItem>>.broadcast();

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
  }) async {
    _messages.add(ChatItem(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: HarnessConfig.ownerRole,
      text: text,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    _controller.add(_snapshot);
  }
}
